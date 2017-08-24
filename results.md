# Results

## Number comparisons

- Core content items :white_check_mark:
    - Drupal (article, article_full, audio, video, slideshow): 57868
    - WordPress (post; audio, video, and gallery are formats): 57868 (there was a one node difference until we added the video content type. unsure why but this isn't concerning at this time)
    - Permalink structures for these core types:
        - article: [field_department-path]/[yyyy]/[mm]/[title-raw]
        - article_full: [field_department-path]/[yyyy]/[mm]/[title-raw]
        - audio: [field_department-path]/[yyyy]/[mm]/[title-raw]
        - video: [field_department-path]/[yyyy]/[mm]/[title-raw]
        - slideshow: [field_department-path]/[yyyy]/[mm]/[title-raw] (we had to force a category for all the slideshow items so that the redirect would work)
- Pages :white_check_mark:
    - Drupal: 55
    - WordPress: 55
- Newsletters: :white_check_mark:
    - Drupal: 2051 (daily: 1593, greater mn: 266, book club: 1, sunday review; 186, washington: 5)
    - WordPress: 2051 (daily: 1593, greater mn: 266, book club: 1, sunday review; 186, washington: 5)
- Comments :white_check_mark:
    - Drupal: 198659
    - WordPress: 198659
- Users (skips user with ID of 0; results correct) :white_check_mark:
    - Drupal: 54544
    - WordPress: 54543
- Authors :white_check_mark:
    - Drupal: 2018
    - WordPress: 2018
- Article / author pairs :white_check_mark:
    - Drupal: 54901
    - WordPress: 54901
- Category :white_check_mark:
    - Department/Column + Section (Drupal): 75
    - Category (WordPress): 75
- post/category / node/section/department combinations: :white_check_mark:
    - Drupal: 117907
    - WordPress: 109057
    - I think this is okay; the only mismatches are in the Drupal nodes that are both sections and departments. I think they're still being counted twice.
- post/category / node/section/department combinations by name: :white_check_mark:
    - Drupal: 75 pairs, skipping the department pairs because the section pairs are already counted
    - WordPress: 75 pairs
- Tags :white_check_mark:
    - Drupal: 7810
    - WordPress: 7810
- post/tag / node/term combinations :white_check_mark:
    - Drupal: 133512
    - WordPress: 133512
- post/tag / node/term combinations by name: :white_check_mark:
    - Drupal: 7810 pairs, including 853 that have 0 results
    - WordPress: 6957 pairs. Adding 853 (WordPress does not create relationships where there are no posts) makes 7810.
- Images
    - need to think about how to count this properly
        - Feature :white_check_mark:
        - Thumbnail :white_check_mark:
        - Detail :white_check_mark:
        - Author :white_check_mark:
        - Featured Column :white_check_mark:
        - make sure we define all the sizes correctly
    - Folders to migrate to database
        - /sites/default/files/imagecache/article_detail :white_check_mark
        - /sites/default/files/imagecache/article_inset :white_check_mark
        - /sites/default/files/imagecache/author_photo :white_check_mark:
        - /sites/default/files/imagecache/author_teaser :white_check_mark:
        - /sites/default/files/imagecache/feature :white_check_mark:
        - /sites/default/files/imagecache/feature_large :white_check_mark:
        - /sites/default/files/imagecache/feature_middle :white_check_mark:
        - /sites/default/files/imagecache/featured_column :white_check_mark:
        - /sites/default/files/imagecache/gallery :white_check_mark
        - /sites/default/files/imagecache/image_detail :white_check_mark:
        - /sites/default/files/imagecache/newsletter_thumb
        - /sites/default/files/imagecache/sidebar_middle
        - /sites/default/files/imagecache/sidebar_right
        - /sites/default/files/imagecache/slideshow_image
        - /sites/default/files/imagecache/thumbnail :white_check_mark
- Redirects :white_check_mark:
    - Drupal: 51390
    - WordPress: 51390
- Other content items to investigate
    - Custom Spill :white_check_mark:
    - Image (has a thumbnail as well as a big image)
- Author / user information
    - We have user member level and member level capabilities (and with the Salesforce plugin, they sync as they should). :white_check_mark:
    - We need to figure out how to map the Drupal roles to WordPress capabilities - which ones we can map directly vs which ones we have to create, and how we can create them (probably with a plugin)
    - Custom fields for authors and users
- Category / tag information :white_check_mark:
    - Categories have several custom fields, and a custom display at their url
- Custom fields on core content
    - Deck :white_check_mark:
    - Byline :white_check_mark:
    - Teaser :white_check_mark:
    - Thumbnail image :white_check_mark:
    - Homepage Image Size :white_check_mark:
    - Main Image Credit :white_check_mark:
    - Main Image Caption :white_check_mark:
    - Inline Images :white_check_mark:
    - Show Author Info?
    - Related Content
    - Related Multimedia
    - File attachments (these get added to the story inline, and we don't need to list them at the end) :white_check_mark:
    - DocumentCloud Document :white_check_mark:
    - Sidebar
    - Meta tags
    - Menu settings
    - Comment settings :white_check_mark:
    - Path settings
    - URL redirects :white_check_mark:
    - Content Access Level
    - MinnPost+ Icon Style
- Menus
    - Primary :white_check_mark:
    - Secondary :white_check_mark:
    - Support :white_check_mark:
    - Network :white_check_mark:
    - Footer Primary :white_check_mark:
    - Footer Secondary :white_check_mark:
- Analytics functionality
- Modals
- Sidebar items that aren't custom spills
    - featured columns (on categories) :white_check_mark:
    - featured columns (on homepage) :white_check_mark:
    - glean (on homepage) :white_check_mark:
    - subscribe form for dc
    - who's running
    - data & maps
- Access to items based on user info

### Notes

- Wrote a plugin that splits the Drupal image metadata into alt, caption, etc. It can be used for as many types as necessary, but is currently only being used for thumbnail images. It's likely we won't need it for inline images, but maybe will need it for detail ones.
- bylines seem to throw things off because they don't necessarily correspond to authors or users
    - this is fine
- need user roles and permissions
- user fields were only saved if the user has ever saved their account. otherwise it is somewhere not in the database. need to figure out what i was talking about here.
- alt text, captions, whatever else for all images are in a serialized row in drupal. there seem to be some differences with the section/department nodes
- wrote a plugin to create the custom spills as sidebar widgets. however they can't be migrated into the database directly because they are stored in the wp_options table as a big serialized mess.
    - We're using a plugin that can export/import widget settings because of this.
    - This will be useful for any kind of widgets we have to create.
- We're using the Merge duplicate terms plugin to merge tags that Drupal has in multiple taxonomies because we don't need this for WordPress.
    - This will reduce the total count of tags.
    - It also takes forever to run because there are a lot of duplicates.
    - No duplicate categories are created by our migration queries.
- there is a field_image_thumbnail field that is almost useless.


### Content fields we don't have to migrate

1. field_center_intro
2. field_center_main_image
3. field_center_related
4. field_center_title
5. field_download
6. field_ec_featured_nodes
7. field_op_embedded_image
8. field_left_intro
9. field_right_intro
10. field_right_related
11. Also a bunch of election fields: field_elecitons_date, field_elections_2012_primary_per, field_elections_2012_primary_won, field_elections_amount_raised, field_elections_boundary_id, field_elections_c_address, field_elections_candidate_image, field_elections_candidates, field_elections_cash_on_hand, field_elections_caucus_date, field_elections_district, field_elections_email, field_elections_expenditures, field_elections_f_candidates, field_elections_facebook_profile, field_elections_finance_board_id, field_elections_financials_upd, field_elections_first_name, field_elections_incumbents, field_elections_last_name, field_elections_os_legislator, field_elections_outside_news, field_elections_phone, field_elections_primary_date, field_elections_pvi, field_elections_r_address, field_elections_seats_available, field_elections_twitter_username, cfield_elections_watchable, field_elections_website, group_elections_2012_primary, field_elections_2012_primary_per, field_elections_2012_primary_won, gorup_elections_financials, group_elecitons_contact_info
12. There's a sidebar field (field_sidebar_value) - 3200+ nodes (does include revisions) have a value here. need to figure out what to do with it. article, department, event, page are the node types. Grouping it by vid reduces it to 698 rows


### Content types we don't have to migrate

1. Editor's Choice (empty)
2. Long answer question (empty)
3. Matching question (empty)
4. Package (empty)
5. Scale question (empty)
6. Short answer question (empty)
7. Resource (empty)
8. Voting District
9. Webform
10. Multiple choice question
11. Quiz
12. Quiz directions
13. True/False question
14. Election (related to that elections group of modules)
15. Candidate (related to that elections group of modules)


### File folders we don't have to migrate into database

1. /sites/default/files/imagecache/400xY
2. /sites/default/files/imagecache/elections_candidate_image
3. /sites/default/files/imagecache/featured_image
4. /sites/default/files/imagecache/package_featured
5. /sites/default/files/imagecache/imagefield_default_images
6. /sites/default/files/imagecache/js-remove
7. /sites/default/files/op_imgbox


### Special Drupal things that will break

1. https://www.minnpost.com/data/2012/09/interactive-who-will-control-2013-minnesota-legislature
2. http://minnpost-wordpress.dev/data/2012/10/my-elections-explore-2012-races-your-address/