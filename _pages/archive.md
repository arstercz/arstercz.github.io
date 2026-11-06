---
layout: page
author: "arstercz"
title: "Archive"
permalink: /archive/
---

{% if site.posts.size == 0 %}
<p>No post found</p>
{% endif %}
{% assign last_year = '' %}
{% for post in site.posts %}
{% assign year = post.date | date: '%Y' %}
{% if year != last_year %}
{% unless forloop.first %}</ul>{% endunless %}
<h2 class="archive-year">{{ year }}</h2>
<ul class="archive">
{% assign last_year = year %}
{% endif %}
<li><time>{{ post.date | date: "%m-%d" }}</time>{% if post.link %}<a href="{{ post.link }}">{{ post.title }}</a>{% else %}<a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a>{% endif %}</li>
{% if forloop.last %}</ul>{% endif %}
{% endfor %}
