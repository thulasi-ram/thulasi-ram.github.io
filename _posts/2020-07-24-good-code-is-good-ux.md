---
layout: post
title: Demystifying celery - Part 2 - Embracing
tags: [programming, blog]
status: wip
permalink: /:title
---

This post works upon internal library kombu used by celery for amqp transport mechanisms. For people that are not a option visit blog one where we [extend the functionality of celery](/demystifying-celery-part-1-customizing)

1. Gotchas of celery
	1. celery events gossip
	2. celery canvas large payloads
	3. The code
	4. Metadata celery uses
	5. Unintutive defaults

2. But I want resilience of celery
3. dead letter queues !!!
4. But but but where are my retries and delayed tasks?
