---
layout: post
title: Microservices are hard
tags: [programming, rant]
permalink: /blog/:title/
---

#### /rant

Random day today like all other days but there was this idea still fresh in my mind from the yesterdays AWS Summit Online about microservices.
There was a discussion by elara tech and how they have used microservices patterns to scale. Some of mentioned patterns include
* ratelimiting
* api gateway
* circuit breaker
* bulk heading
* automatic retyring and caching 
and other resilience techniques.

They have 50+ micorservices. In a fictional company I had worked earlier we had 100+ plus microservices.

During a discussion based on a security audit we figured we were not validating the auth token in the graphql layer.
To fix that we were supposed to call auth service from graphql for each request and auth service was slow.
The immediate suggestion was to cache the auth token in redis from graphql along with its expiry during login, refresh them on expiry and bust them on logout.

This call is one of what I call as snowball blunder. These gradually roll up and cause an avalanche. We playfully roll the ice ball without considering its consequences. What can a puffy small snowball do? Splash on your face? Meh.


1. Arent we implementing auth again in graphql? What is the role of auth then?
2. What happens when redis cluster crashes? You implement a fallback or you log the users out?
3. Now how do you take care of fallbacks?

We had no circuit breaker, we had no bulk heading, we had not thought of fallbacks.
We had a half baked loadbalancer as an api gateway, a half baked caching and we had not thought of retries.

But yeah we are on microservices. If someone asks we can proudly say yeah we are on microservices and even worse have 100s of them.

Although not all hope is lost. We do have a good sense of where we went wrong. We had do to all this because auth was slow.
If only the service was fast we would not have needed any of the above. So lets rewrite it using go.