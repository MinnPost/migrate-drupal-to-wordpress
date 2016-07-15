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
    - no idea how to count this in Drupal (also the permalinks will maybe need to be redirects, if they even get traffic)
- Taxonomy / article pairs
    - 
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
    - Directed Message
    - Election (related to that elections group of modules)
    - Event
    - FAN Club Vote
    - Image (has a thumbnail as well as a big image)
    - Multiple choice question
    - Newsletter
    - Package
    - Panel
    - Partner
    - Partner Offer
    - Partner Offer Instance
    - Quiz
    - Quiz directions (see if we've used this)
    - Sidebar Item (has a thumbnail)
    - Slideshow (has a thumbnail)
    - Sponsor
    - True/False question (see if we've used this)
- Author / user information
- Custom fields on core content
- Analytics functionality
- Modals
- Sidebar items
    - Sidebar item

### Notes

- Need to figure out what to do with all custom fields
- bylines seem to throw things off because they don't necessarily correspond to authors or users
    - this should be fixed by Largo as I think it has a byline field
- need user roles and permissions
- user fields were only saved if the user has ever saved their account. otherwise it is somewhere not in the database. need to figure out what i was talking about here.
- alt text, captions, whatever else for all images are in a serialized row in drupal. there seem to be some differences with the section/department nodes



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