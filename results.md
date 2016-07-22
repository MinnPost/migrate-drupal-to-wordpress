# Results

## Number comparisons

- Core content items
    - Drupal (article, article_full, audio, video): 55335
    - WordPress (post): 55335 (there was a one node difference until we added the video content type. unsure why but this isn't concerning at this time)
- Pages
    - Drupal: 51
    - WordPress: 51
- Comments
    - Drupal: 187623
    - WordPress: 187623
- Users (skips user with ID of 0; results correct)
    - Drupal: 52976
    - WordPress: 52975
- Authors
    - Drupal: 2001
    - WordPress: 2001
- Article / author pairs
    - Drupal: 53317
    - WordPress: 52962 (this is correct because Drupal counts pairs where there is a blank value; ex if there is a byline field)
- Category
    - Department/Column + Section (Drupal): 75
    - Category (WordPress): 75
- Tags
    - no idea how to count this in Drupal because the term table is just one big thing
- post/tag / node/term combinations
    - Drupal: 127070
    - WordPress: 127070
- Images
    - need to think about how to count this properly
        - Feature
        - Thumbnail
        - Detail
        - Author
        - make sure we define all the sizes correctly
- Other content items to investigate
    - Candidate (related to that elections group of modules)
    - Custom Spill
    - Election (related to that elections group of modules)
    - Image (has a thumbnail as well as a big image)
    - Multiple choice question
    - Quiz
    - Quiz directions (see if we've used this)
    - Slideshow (has a thumbnail)
    - True/False question (see if we've used this)
- Author / user information
- Custom fields on core content
- Analytics functionality
- Modals
- Sidebar items

### Notes

- Wrote a plugin that splits the Drupal image metadata into alt, caption, etc. It can be used for as many types as necessary, but is currently only being used for thumbnail images. It's likely we won't need it for inline images, but maybe will need it for detail ones.
- Need to figure out what to do with all custom fields
- bylines seem to throw things off because they don't necessarily correspond to authors or users
    - this should be fixed by Largo as I think it has a byline field
- need user roles and permissions
- user fields were only saved if the user has ever saved their account. otherwise it is somewhere not in the database. need to figure out what i was talking about here.
- alt text, captions, whatever else for all images are in a serialized row in drupal. there seem to be some differences with the section/department nodes


### Content fields we don't have to migrate

1. field_center_intro
2. field_center_main_image (if we can fix the sponsor)
2. field_center_related
3. field_center_title
4. field_download
5. field_ec_featured_nodes
6. field_left_intro
7. field_right_intro
8. field_right_related
9. Also a bunch of election fields: field_elecitons_date, field_elections_2012_primary_per, field_elections_2012_primary_won, field_elections_amount_raised, field_elections_boundary_id, field_elections_c_address, field_elections_candidate_image, field_elections_candidates, field_elections_cash_on_hand, field_elections_caucus_date, field_elections_district, field_elections_email, field_elections_expenditures, field_elections_f_candidates, field_elections_facebook_profile, field_elections_finance_board_id, field_elections_financials_upd, field_elections_first_name, field_elections_incumbents, field_elections_last_name, field_elections_os_legislator, field_elections_outside_news, field_elections_phone, field_elections_primary_date, field_elections_pvi, field_elections_r_address, field_elections_seats_available, field_elections_twitter_username, cfield_elections_watchable, field_elections_website


### Content types we don't have to migrate

1. Editor's Choice (empty)
2. Long answer question (empty)
3. Matching question (empty)
2. Package (empty)
3. Scale question (empty)
4. Short answer question (empty)
2. Resource (empty)
2. Voting District
2. Webform


### Other things to create

- Directed Message
- Event
- FAN Club Vote
- Newsletter
- Panel
    - Node template
        - Author page (makes it a single column; gives it a css id; tells it to get 10 nodes from the author)
        - Section page (minnpost listing like homepage; lets you feature 1 node then load 20; plus a 'section listing' column, 'node being viewed', 'sidebar items homepage' blocks on the side - these presumably handle most commented, recent stories, featured columns, in case you missed it, etc)
        - Department/Column page (minnpost listing like homepage; lets you feature 3 nodes then load 10; plus a 'section listing' column, 'node being viewed', 'sidebar items homepage' blocks on the side - these presumably handle most commented, recent stories, featured columns, in case you missed it, etc)
    - Home page (makes all the columns)
        - Has regions for left side and right side
        - Left
            - Top banner (hidden)
            - Holiday break
            - Nodequeue top
            - Nodequeue middle
            - Ad Middle3
            - Nodequeue bottom
        - Right
            - HP Columns Featured
            - Under Glean sidebar
            - Nodequeue HP Columns
            - Sidebar items
- Partner
- Partner Offer
- Partner Offer Instance
- Sidebar Item (has a thumbnail)
- Sponsor
- Webform
    - The Letter to the Editor form is here
    - There's also a Late in life heatlh care questionnaire from 2014