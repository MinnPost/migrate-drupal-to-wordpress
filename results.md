# Results

## Number comparisons

- Core content items :white_check_mark:
    - Drupal (article, article_full, audio, video): 57455
    - WordPress (post): 57455 (there was a one node difference until we added the video content type. unsure why but this isn't concerning at this time)
- Pages :white_check_mark:
    - Drupal: 55
    - WordPress: 55
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
- post/category / node/section/department combinations:
    - Drupal:
    - WordPress:
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
        - Feature
        - Thumbnail
        - Detail
        - Author
        - make sure we define all the sizes correctly
- Redirects :white_check_mark:
    - Drupal: 51390
    - WordPress: 51390
- Other content items to investigate
    - Custom Spill (remember: this one has a field_departments field that lists relevant departments)
    - Image (has a thumbnail as well as a big image)
    - Slideshow (has a thumbnail)
- Author / user information
    - We have user member level and member level capabilities (and with the Salesforce plugin, they sync as they should).
    - We need to figure out how to map the Drupal roles to WordPress capabilities - which ones we can map directly vs which ones we have to create, and how we can create them (probably with a plugin)
- Custom fields on core content
- Analytics functionality
- Modals
- Sidebar items
- Access to items based on user info

### Notes

- salesforce is a cluster. too much depends on it.
- Wrote a plugin that splits the Drupal image metadata into alt, caption, etc. It can be used for as many types as necessary, but is currently only being used for thumbnail images. It's likely we won't need it for inline images, but maybe will need it for detail ones.
- bylines seem to throw things off because they don't necessarily correspond to authors or users
    - this should be fixed by Largo as I think it has a byline field
- need user roles and permissions
- user fields were only saved if the user has ever saved their account. otherwise it is somewhere not in the database. need to figure out what i was talking about here.
- alt text, captions, whatever else for all images are in a serialized row in drupal. there seem to be some differences with the section/department nodes


### Content fields we don't have to migrate

1. field_center_intro
2. field_center_main_image (if we can fix the sponsor)
3. field_center_related
4. field_center_title
5. field_download
6. field_ec_featured_nodes
7. field_left_intro
8. field_right_intro
9. field_right_related
10. Also a bunch of election fields: field_elecitons_date, field_elections_2012_primary_per, field_elections_2012_primary_won, field_elections_amount_raised, field_elections_boundary_id, field_elections_c_address, field_elections_candidate_image, field_elections_candidates, field_elections_cash_on_hand, field_elections_caucus_date, field_elections_district, field_elections_email, field_elections_expenditures, field_elections_f_candidates, field_elections_facebook_profile, field_elections_finance_board_id, field_elections_financials_upd, field_elections_first_name, field_elections_incumbents, field_elections_last_name, field_elections_os_legislator, field_elections_outside_news, field_elections_phone, field_elections_primary_date, field_elections_pvi, field_elections_r_address, field_elections_seats_available, field_elections_twitter_username, cfield_elections_watchable, field_elections_website, group_elections_2012_primary, field_elections_2012_primary_per, field_elections_2012_primary_won, gorup_elections_financials, group_elecitons_contact_info
11. There's a sidebar field (field_sidebar_value) - 3200+ nodes (does include revisions) have a value here. need to figure out what to do with it. article, department, event, page are the node types. Grouping it by vid reduces it to 698 rows


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


### Special Drupal things that will break

1. https://www.minnpost.com/data/2012/09/interactive-who-will-control-2013-minnesota-legislature
2. http://minnpost-wordpress.dev/data/2012/10/my-elections-explore-2012-races-your-address/