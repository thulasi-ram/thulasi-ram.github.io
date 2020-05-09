---
title: /work
layout: work
permalink: /work
---

# Experience


{% assign curr_mon = site.time | date: '%-m' %}
{% assign curr_day = site.time | date: '%d' %}

{% assign curr_mon = curr_mon | times: 1 %}
{% assign curr_day = curr_day | times: 1 %}

{% assign total_exp = site.time | date: '%Y' | minus:2014  %}


{% if curr_mon < 6 %}
	{% assign total_exp = total_exp | minus: 1 %}
{% elsif curr_mon == 6 and curr_day < 13 %}
	{% assign total_exp = total_exp | minus: 1 %}
{% endif %}

#### Total Exp: {{ total_exp }}+ years
* Treebo (Mar 2018 - present)
* Innoventes Technologies (May 2016 - Feb 2018)  
	+ <small>Contractor with treebo</small>
* Infosys (June 2014 - April 2016)
