# Results

## 4/25/16

- Core content items
    - Drupal (article, article_full, audio): 54901
    - WordPress (post): 54902 (unsure why this is, but not really worried)
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
- Images
    - need to think about how to count this properly
- Taxonomy
    - Department/Column
    - Section
- Other content items to investigate
    - Candidate
    - Custom Spill
    - Directed Message
    - Editor's Choice
    - Election
    - Event
    - FAN Club Vote
    - Long answer (see if we've used this)
    - Matching (see if we've used this)
    - Multiple choice question
    - Newsletter
    - Package
    - Panel
    - Partner
    - Partner Offer
    - Partner Offer Instance
    - Quiz
    - Quiz directions (see if we've used this)
    - Scale question (see if we've used this)
    - Short answer question (see if we've used this)
    - Sidebar Item
    - Slideshow
    - Sponsor
    - True/False question (see if we've used this)
    - Video
- Author / user information
- Custom fields on core content
- Analytics functionality
- Modals
- Sidebar items
    - Sidebar item

### Notes

- Need to figure out what to do with all custom fields
- bylines seem to throw things off because they don't necessarily correspond to authors or users
    - this should be fixed by Largo
- check all the numbers of imported items between the systems
- need user roles and permissions
- need to set top images as featured images. this is at least partially working
- user fields are only saved if the user has ever saved their account. otherwise it is somewhere not in the database



### Content types we don't have to migrate

1. Package (empty)
2. Resource (empty)
2. Voting District
2. Webform