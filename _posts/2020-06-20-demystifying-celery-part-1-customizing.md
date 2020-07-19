---
layout: post
title: Demystifying celery - Part 1 - Customizing
tags: [programming, blog]
permalink: /:title
---

Celery is touted as the async task processor in python. Its resilient, its fast and moreover has large set of utilities and deals with multiple messaging systems.
But there's not one but two problems in it for me. 
1. The learning curve is steep for celery not just the concepts but even the code that resides and worse its configured with unintutive defaults. 
2. It lives upto its name of distributed task processing but its too much of a cake if you just want a simple messaging consumer. 

But sometimes we are stuck. We cannot get rid of it since there are so many things that are managed by it. But what if the producer is not celery? You cannot consume such messages with celery.

In this post we will cover for use cases where we want to retain celery for other tasks but still be able to consume from producers that are not celery. As a bonus we will also setup a dead-letter-queue for our queue so that messages are not discarded. For use cases where getting rid of celery can be considered take look into this flask extension like implementation in part-2 of this post [here](/demystifying-celery-part-2-embracing).


### 1. Custom consumer

Although celery makes it needlessly difficult they luckily provide us with a barebones implementation of a consumer.
[custom-message-consumers - celery docs](https://docs.celeryproject.org/en/stable/userguide/extending.html#custom-message-consumers)
the part we are most concerned is 

```
my_queue = Queue('custom', Exchange('custom'), 'routing_key')

app = Celery(broker='amqp://')


class MyConsumerStep(bootsteps.ConsumerStep):

    def get_consumers(self, channel):
        return [Consumer(channel,
                         queues=[my_queue],
                         callbacks=[self.handle_message],
                         accept=['json'])]

    def handle_message(self, body, message):
        print('Received message: {0!r}'.format(body))
        message.ack()
app.steps['consumer'].add(MyConsumerStep)
```
{: .lang-python}


This can pickup a message thats not published by celery. But what about decode error? What about my retries?

#### Being Ambitious
My first approach was to convert this message to a celery task such that the user is not aware by replicating some of celery's magic (this was discared see [here](#bailing_out). So inside the `MyConsumerStep` I have added the following

```
def __init__(*args, **kwargs):
	self.parent = None

def start(self, parent):
    self.parent = parent
    logger.info(f'Consuming from {queue_obj.name} key={queue_obj.routing_key}, exchange={queue_obj.exchange}')
    return super().start(parent)
```
{: .lang-python}


This parent here is the `celery.worker.Consumer` class. This class stores all the tasks that are in an app in a map called `strategies`.
Strategies in celery knows how to run a task and handle its failures.

Lets say I have a function called `process_message` and now I have to call it in handle message and I want this to be as DRY as possible.

My train of thought would be handle process_mesage as a task. I end up with the following handle messgae:

```
def handle_message(self, body, message):
    task = shared_task(process_message)
    strategy = self.task.start_strategy(self.parent.app, self.parent)
    strategy(
        message, payload,
        promise(call_soon, (message.ack_log_error,)),
        promise(call_soon, (message.reject_log_error,)),
        callbacks,
    )
    .
    .
    .
    following this way you would end having 
    to access process_message.request.body 
    inside `process_message` like you would do for a bound task
    which gets very complicated quickly
```
{: .lang-python}

#### Bailing out {#bailing_out}
We would be using so many internals of celery that makes our code brittle. I bailed out here. I just republish the message here after converting it into a taks. 

```
def handle_message(self, body, message):
    task = shared_task(process_message)
    task.delay(body, message=message)

# now my process_message looks like

def process_message(body, **kwargs):
	pass
```
{: .lang-python}


This gives us the ability to retain the retry mechanisms celery offers and as well as consuming a custom message. A properly honed out version of the above as `celery_consumer.py` by making it as reusable as possible but still encapsulating the internals


```
# celery_consumer.py

import logging

from celery import bootsteps, current_app, Task, shared_task

_registry = {}

logger = logging.getLogger(__name__)

def _custom_consumer_factory(queue, callback, kwargs):
    class BaseCustomConsumer(bootsteps.ConsumerStep):
        requires = (
            'celery.worker.consumer:Connection',
            'celery.worker.consumer.tasks:Tasks',
        )

        def start(self, parent):
            logger.info(f'Consuming from {queue.name} key={queue.routing_key}, exchange={queue.exchange}')
            return super().start(parent)

        def handle_message(self, body, message):
            callback.delay(body)
            message.ack()

        def on_decode_error(self, message, exc):
            message.reject()

        def get_consumers(self, channel):
            options = {
                'accept': ['json']
            }
            consumer_options = kwargs.pop('consumer_options', {})
            options.update(consumer_options)
            return [
                Consumer(
                    channel,
                    queues=[queue],
                    callbacks=[self.handle_message],
                    on_decode_error=self.on_decode_error,
                    **options
                )
            ]

    return type(f'{queue.name}Consumer', (BaseCustomConsumer,), {})


def _make_consumer(func, **kwargs):
    from kombu import Queue

    queue = kwargs.pop('queue', None)

    if not queue:
        raise RuntimeError("queue is a required parameter for consume_from")
    if isinstance(queue, Queue):
        queue_obj = queue
    else:
        _qoptions = {'no_declare': False}
        queue_options = kwargs.pop('queue_options', {})
        _qoptions.update(queue_options)
        queue_obj = Queue(queue, **_qoptions)

    return _custom_consumer_factory(queue_obj, func, kwargs), queue_obj


def consume_from(*args, **kwargs):
    """
    :param args: empty. will resolve to the wrapped function
    :param kwargs: queue - either string or kombu.Queue Instance, and other kwargs of kombu.Queue
    :return: the wrapped function

    Usage
    -----

    a)
    @consume_from(queue='<queue_name>', routing_key='<rk>')
    def process_message(body, message):
        pass


    b)
    exchange = Exchange("example", "topic")
    queue = Queue("example", exchange, routing_key="com.example")

    @consume_from(queue=queue)
    def process_message(body, message):
        pass

    """

    def decorator(**options):
        def __inner(func):
            consumer, queue = _make_consumer(func, **options)

            if queue.name in _registry:
                raise RuntimeError(f"Already registered {_registry[queue.name]} for {queue.name}")
            logger.info(f"Registering: {func} for queue {queue.name} and routing key {queue.routing_key}")
            _registry[queue.name] = func
            current_app.steps['consumer'].add(consumer)

            if not isinstance(func, Task):
                return shared_task(func)
            return func

        return __inner

    if len(args) == 1 and callable(args[0]):
        return decorator(**kwargs)(args[0])
    return decorator(*args, **kwargs)

```
{: .lang-python}


So now process message looks like

```
from celery_consumer import consume_from

@consume_from(queue='custom_queue', routing_key='#')
def process_event(body):
    pass

# (or)

@consume_from(queue='custom_queue', routing_key='#')
@shared_task(autoretry_for=(Exception,), retry_backoff=2)
def process_event(body):
	pass
```
{: .lang-python}


### 2. Dead letter queues in celery go brrrrrrr


This problem applies to both aspects here. firstly what if a celery task fails even after retries? Its ignored and the state is stored in a result backend. Secondly what happens if the message from the custom queue encounters an decode error? we dont store that at all since its a custom message.

Enter dead letter queues, But there's no provision of deadletter queues in celery you will have to set it up by default.

here is the `celery_dlq.py` file

```
# celery_dlq.py

from celery import bootsteps
from kombu import Queue, Exchange


def setup_default_dlq(app, dlq_suffix='dead'):
    queue = Queue(
        app.conf.task_default_queue,
        Exchange(app.conf.task_default_exchange, type='direct'),
        routing_key=app.conf.task_default_routing_key
    )
    setup_dlq(app, queue, dlq_suffix)
    app.conf.task_queues = (queue,)


def setup_dlq(app, queue: Queue, dql_suffix='dead'):
    deadletter_queue_name = f'{queue.name}.{dql_suffix}'
    deadletter_exchange_name = f'{queue.name}.{dql_suffix}'
    deadletter_routing_key = f'{queue.routing_key}.{dql_suffix}'

    if queue.queue_arguments is None:
        queue.queue_arguments = {}
    queue.queue_arguments.update({
        'x-dead-letter-exchange': deadletter_exchange_name,
        'x-dead-letter-routing-key': deadletter_routing_key
    })

    class DeclareDLXnDLQ(bootsteps.StartStopStep):
        """
        Celery Bootstep to declare the DL exchange and queues before the worker starts
            processing tasks
        """
        requires = {'celery.worker.components:Pool'}

        def start(self, worker):
            dlx = Exchange(deadletter_exchange_name, type='direct')

            dead_letter_queue = Queue(
                deadletter_queue_name, dlx, routing_key=deadletter_routing_key)

            with worker.app.pool.acquire() as conn:
                dead_letter_queue.bind(conn).declare()

    app.steps['worker'].add(DeclareDLXnDLQ)
```
{: .lang-python}


As you can see here we use a start and stop step to declare a dlq. More details can be found [here](https://medium.com/@hengfeng/how-to-create-a-dead-letter-queue-in-celery-rabbitmq-401b17c72cd3).
When the celery app starts we can do something like this
```
app = Celery('amqp://')
app.autodiscover_tasks()
setup_default_dlq(app)
```
{: .lang-python}


This creates `celery.dead` exchange and queue for all the failed messages to live so we can inspect it later. 
Now use this `setup_dlq` to our earlier `_make_consumer` to automatically declare if a flag is present.


```
def _make_consumer(func, **kwargs):
    from kombu import Queue

    queue = kwargs.pop('queue', None)

    if not queue:
        raise RuntimeError("queue is a required parameter for consume_from")
    should_setup_dlq = bool(kwargs.get('setup_dlq'))  # added newly
    if isinstance(queue, Queue):
        queue_obj = queue
    else:
        _qoptions = {'no_declare': not should_setup_dlq}  # added newly
        queue_options = kwargs.pop('queue_options', {})
        _qoptions.update(queue_options)
        queue_obj = Queue(queue, **_qoptions)

    # added newly
    if should_setup_dlq:
        setup_dlq(current_app, queue_obj)

    return _custom_consumer_factory(queue_obj, func, kwargs), queue_obj
```
{: .lang-python}


now process event looks like with an extra `setup_dlq=True`

```
@consume_from(queue='example', routing_key='com.example', setup_dlq=True)
@shared_task(autoretry_for=(Exception,), retry_backoff=2)
def process_event(body):
    print(f"Received yoyo: {body}")
```
{: .lang-python}

