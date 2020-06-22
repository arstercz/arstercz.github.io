---
layout: post
author: "arstercz"
title: "Archive"
permalink: /archive/
---

{% if site.posts.size == 0 %}
  <h2>No post found</h2>
{% endif %}

<ul class="archive">
  {% for post in site.posts %}
    {% unless post.next %}
      <h2>{{ post.date | date: '%Y' }}</h2>
    {% else %}
      {% capture year %}{{ post.date | date: '%Y' }}{% endcapture %}
      {% capture nyear %}{{ post.next.date | date: '%Y' }}{% endcapture %}
      {% if year != nyear %}
        <h2>{{ post.date | date: '%Y' }}</h2>
      {% endif %}
    {% endunless %}

    <li>
      <time>{{ post.date | date: "%m-%d" }}</time>
      {% if post.link %}
      <a href="{{ post.link }}">
      {% else %}
      <a href="{{ site.baseurl }}{{ post.url }}">
      {% endif %}
        {{ post.title }}
      </a>
    </li>
  {% endfor %}
</ul>
