#!/usr/bin/perl

# WordPress migration for Statocles
#
# Copyright (c) 2016 by William Lindley <wlindley@wlindley.com>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use v5.20;
use warnings;
use strict;

use HTML::TreeBuilder;
use HTML::Element;

sub rectify_html {
    # WordPress uses a variant of HTML in which blank lines indicate
    # paragraph breaks.  Here we translate those into a semblance of standard
    # HTML, ensuring that blank lines inside <pre> blocks do not get changed.
    # We also ensure that comments in the HTML are retained.

    my $munged_text = shift;

    my @pre_segments;  # Stash for the <pre> blocks.
    my $seg_id=0;      # Number each block.
    $munged_text =~ s{<pre\b(.*?)>(.*?)</pre\s*>}
                     {$pre_segments[++$seg_id]=$2; "<pre data-seg=\"$seg_id\"$1></pre>";}gsex;
    $munged_text =~ s/\n\s*\n/\n<p>/g;

    my $atree = HTML::TreeBuilder->new();

    # Prepare to store comments, for which HTML::TreeBuilder requires wrapping in <html><body>
    $atree->store_comments(1);
    $atree->p_strict(1);  # ensure things like multi-paragraph blockquotes get properly nested

    $atree->parse("<html><body>$munged_text</body></html>");

    # Replace original text contents for <pre> elements
    foreach my $pre_element ($atree->look_down('_tag', 'pre')) {
    	my $segment_text = $pre_segments[$pre_element->attr('data-seg')];

        # These transformations are not guaranteed to make applesauce of your
        # text, particularly if you have e.g., "&amp;amp;" or such things
        $segment_text =~ s/&lt;/</g;
        $segment_text =~ s/&gt;/>/g;
        $segment_text =~ s/&amp;/&/g;

    	# double-quote % signs in <pre> to prevent Mojo template from seeing
    	$segment_text =~ s/<%/<%%/g;

        # Quote leading % to %%
        $segment_text =~ s/^(\s*)%/$1%%/gm;

        # http://daringfireball.net/projects/markdown/syntax#autoescape
        # − "inside Markdown code spans and blocks, angle brackets and
        # ampersands are always encoded automatically."
        $pre_element->push_content($segment_text);

	$pre_element->attr('data-seg',undef);
    }

    return $atree->as_HTML(undef, ' ', {});   # Convert object tree back to simple string
}

###############

sub blog_style_date {
    # Convert an arbitrary text date into YYYY/MM/DD format
    my $text_date = shift;

    # year,month,day from array returned by Date::Parse …
    my ($year, $month, $day) = (strptime($text_date))[5,4,3];
    return undef unless defined $year;
    return sprintf("%04d/%02d/%02d", $year+1900, $month+1, $day);
}

###############

# Read input, presumably a WordPress export file, and parse XML tree

use XML::Simple qw(:strict);
binmode(STDOUT, ":utf8");   # enable Unicode output

my $xs = XML::Simple->new();
my $ref = $xs->XMLin($ARGV[0], ForceArray => 1, KeyAttr => []);

###############

use HTML::FormatMarkdown;
#use YAML::XS;   # seems to emit our 'tag' arrays incorrectly?
use YAML;
use File::Path qw(make_path);
use Path::Tiny;
use Date::Parse;

# ~~~ TODO: Included as hook for future support.
# As of January 2016, Statocles does not yet support post/page workflow status.
#
my %status_map = ( draft => 'draft', private => 'private', publish => 'published' );

# Default values taken from site.yml created by command:  $  statocles create   ---:
my $site = {
            'site' => {
                       'class' => 'Statocles::Site',
                       'args' => {
                                  'apps' => {  # User may want to add/remove some
                                             'static' => {
                                                          '$ref' => 'static_app'
                                                         },
                                             'page' => {
                                                        '$ref' => 'page_app'
                                                       },
                                             'blog' => {
                                                        '$ref' => 'blog_app'
                                                       }
                                            },
                                  'base_url' => 'http://www.~~~.com/',  # take from WP
                                  'title' => '~~~',                     #   "   "
                                  'theme' => { '$ref' => 'theme' },
                                             # 'site/theme',            # ~~~ TODO: or: What is a reasonable default?
                                  'index' => '/page',
                                  'nav' => {
                                            'main' => [                 # TODO: Take from WP, possibly add others?
                                                       {
                                                        'href' => '/blog',
                                                        'text' => 'Blog'
                                                       },
                                                      ]
                                           },
                                  'plugins' => {
                                                'link_check' => {
                                                                 '$class' => 'Statocles::Plugin::LinkCheck'
                                                                }
                                               },
                                  'deploy' => {
                                               '$ref' => 'deploy'
                                              },
                            },
                      },
            'theme' => {
                        'class' => 'Statocles::Theme',
                        'args' => {
                                   'store' => '::default'
                                  }
                       },
            'page_app' => {
                           'class' => 'Statocles::App::Basic',
                           'args' => {
                                      'store' => 'page',   # should match $page_base_dir, below
                                      'url_root' => '/', # ~~~ TODO: match to existing WP site?
                                     }
                          },
            'blog_app' => {
                           'class' => 'Statocles::App::Blog',
                           'args' => {
                                      'store' => 'blog',  # should match $post_base_dir, below
                                      'url_root' => '/', # ~~~ TODO: match to existing WP site?
                                     },
                          },
            'static_app' => { # default location
                             'class' => 'Statocles::App::Basic',
                             'args' => {
                                        'store' => 'static',
                                        'url_root' => '/static', # ~~~ TODO: match to existing WP site?
                                       },
                            },
            'deploy' => { # User will probably want to change later
                         'class' => 'Statocles::Deploy::File',
                         'args' => {
                                    'path' => '.'
                                   },
                        },
           };



my $posts = $ref->{channel}[0]->{item};

# 'wp:post_type': 'post' or 'page' − handle appropriately
# 'wp:status': 'draft' 'private' 'publish' − Later: Probably save this
#   as a draft flag.  For now discard any unpublished.
# 'dc:creator': "bill"
#   -- Use as Statocles: "author"
# 'title': use as Statocles: "title"
# 'wp:post_date': use as Statocles: "date"  [also consider 'wp:post_date_gmt']
# 'category': an array of hashes including post tags; process if follows example:
#    [{domain => 'post_tag', content => 'command line'},
#     {domain => 'post_tag', content => 'Uncategorized'}]
# and turn into 'tags' array
# 'wp:menu_order': numeric. Need to regard this, at each subdirectory level,
#   as the ordering in the site.yaml file

# ~~~ TODO: Consider making these user-definable
my $post_base_dir = path("./blog");  # Where the markdown files and resources are on our local filesystem
my $page_base_dir = path("./page");

# ~~~ TODO: Use more various cpan modules

# Set site's global data from WP config
use Mojo::URL;

my $url_base = Mojo::URL->new($ref->{channel}[0]->{'wp:base_site_url'}[0]);
# e.g., http://www.wlindley.com  (usually without trailing '/')

# If just http://www.example.com  -- add explicit root path:
$url_base->path('/') unless length($url_base->path);

# ~~~ NOTE: Probably want to do something clever with wp:base_blog_url - how do we define the mapping to be consistent?
$site->{site}->{args}->{base_url} = $url_base->to_string;
$site->{site}->{args}->{title} = $ref->{channel}[0]->{title}[0];

my %pages; # Accumulate the entire site here

foreach my $post (@{$posts}) {
    if ($post->{'wp:post_type'}[0] =~ /^post|page$/) {

        my %post_info = (
                         status => $status_map{$post->{'wp:status'}[0]},
                         author => $post->{'dc:creator'}[0],
                         title  => $post->{'title'}[0],
                         date   => $post->{'wp:post_date'}[0],
                         data   => { post_type      => $post->{'wp:post_type'}[0],
                                     wp_post_name   => $post->{'wp:post_name'}[0],
                                     wp_post_path   => $post->{'link'}[0],
                                     wp_post_id     => $post->{'wp:post_id'}[0],
                                     wp_post_parent => $post->{'wp:post_parent'}[0],
                                     wp_menu_order  => $post->{'wp:menu_order'}[0],
                                     # And possibly also custom-post-type info?
                                     },
                        );

        # ~~~ TODO: Add provision for draft pages/posts
        # ~~~ For now, just ignore all unpublished items
        next unless ($post_info{status} eq 'published');

        my @tags;
        my @other_categories;
        foreach my $taxonomy (@{$post->{category}}) {
            next unless ref $taxonomy; # Very old export files contain bare strings in addition the hash we want
            if ($taxonomy->{domain} eq 'post_tag') {
                push @tags, $taxonomy->{content};
            } else {
                push @other_categories, $taxonomy;
            }
            # could also keep @categories for taxonomy 'category'
        }
        $post_info{tags} = \@tags if (scalar @tags);
        $post_info{data}->{categories} = \@other_categories if scalar @other_categories;

        my $p = $post_info{data};
        my $post_basename = $p->{wp_post_name}; 
        my $post_path = $p->{wp_post_path};
        my $is_home_page;

        next if ($post_path =~ m/[?]/);   # Does not have a well-formed URL: probably a draft. Skip this.
        $post_path =~ s/^$url_base//;    # Strip off http://www.example.com
        if (!length($post_path)) {  # this is the site's index
            $post_path = '/index';
            $is_home_page = 1;
        }

        $post_path = path($post_path);   # Convert to Path::Tiny object
        print "  ($post_path)\n";

        my $blog_style_path = blog_style_date($post_info{date});
        next unless defined $blog_style_path;

        my $new_path;

        if ($post_info{data}->{'post_type'} eq 'post') {
            $new_path = $post_base_dir->child($blog_style_path,$post_basename); # becomes directory name
            $post_basename = 'index';
        } else { # Page …
            $new_path = $page_base_dir->child($post_path->parent); # strip the basename for just the directory
            # $post_basename is post name within that.
        }

        my $create_path;
        if ($is_home_page) {
            $post_basename = 'index';
        }
        $create_path= $new_path->child($post_basename);  # Tentative path as seen by browser

        # print "  [$create_path]\n";
        if (defined $pages{$create_path}) {
            warn "   Conflict with existing page at $create_path:\n" .
              "     $post_info{title}\n";
            next;
        }

        # To avoid a bug in HTML::FormatMarkdown, prepend cipher
        my $cipher = '~~1~~';
        my $content = $cipher . $post->{'content:encoded'}[0];
        $content = HTML::FormatMarkdown->format_string(rectify_html($content));
        $content =~ s/$cipher//;  # And remove it after 

        $pages{$create_path} = {
                                path => $new_path,
                                filename => $post_basename,   # WAS: $create_path . '.markdown',
                                header => Dump(\%post_info),  # needs to be followed by line: "---"
                                content => $content,
                               };
        if ($is_home_page) {
            $pages{$create_path}->{home} = 1;
        }
        # NOTE: We might want to create a mapping file from old URLs to new URLs
        # á la .htaccess redirects

    }
}

my %page_children;

foreach my $apage (keys %pages) {
    my $parent = $pages{$apage}->{path};
    my $leaf   = $pages{$apage}->{filename};
    while (defined $parent && ($parent ne '.')) {
        push @{$page_children{$parent}}, $leaf;
        # Traverse up one level
        ($parent, $leaf) = ($parent->parent, path($parent->basename)->child($leaf));
        last if exists $page_children{$parent}; # unless we already know about that
    }
}

foreach my $apage (keys %pages) {
    my $file_path = $pages{$apage}->{path};
    my $file_name = $pages{$apage}->{filename};
    if (defined $page_children{$apage}) {
        # This page has children: make it the index of a new subdirectory
        $file_path = $file_path->child($file_name);
        $file_name = 'index';
    }

    # print "  [$file_path] [$file_name]\n";

    # Actually write each file in appopriate directory
    make_path($file_path);
    open NEWFILE, '>:encoding(UTF-8)', $file_path->child($file_name . '.markdown');
    print NEWFILE $pages{$apage}->{header} . "---\n";
    print NEWFILE $pages{$apage}->{content};
    close NEWFILE;

}

# Write default Site Configuration

open SITE, '>:encoding(UTF-8)', 'site.yml';
print SITE Dump($site);
close SITE;
