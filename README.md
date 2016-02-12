# wp2statocles
Migration tool for bringing WordPress export XML files into Statocles

So far, this tool is fairly rudimentary and only attempts to convert the standard
WordPress posts and pages to markdown files in blog/ and page/ subdirectories per
Statocles style.  Images and other resources like themes, plugins, and custom
post types are simply ignored, and will require manual intervention to copy and
translate.  I do plan to add some further automation, when time and money permit.

No test cases are provided yet; I only have client files for my testing at this point.
Suggestions on this and other subjects would be greatly appreciated.

In future, there is much that could be done to make the migration of a WP site to Statocles
relatively painless.  To consider:

  - making as many identical URLs as possible
  - writing forwarding/redirection rules for many/most existing pages/posts/resources
  - handling of some common Custom Post Types

but the universe of all possible WP sites is huge.

Here we simply handle the contents of the common variety posts and pages.
No attempt is made at making compatible URLs for Posts. 
Rather, they are normalized to the Statocles standard /blog/YYYY/MM/DD/post_name

NOTE: This currently prepends the title to each post/page created, to work
around a [bug in HTML::FormatMarkdown](https://rt.cpan.org/Public/Bug/Display.html?id=111783)

