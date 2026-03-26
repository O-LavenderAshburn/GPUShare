## Things to do

> Whenever any of these are completed, ensure you check it off in this file. Also update the changelog.md file

- [x] Add per-user customisation for 'auto' model

As a user I want to be able to go into settings, and pick from a list the 'light' model used, and the 'heavy' model. This should save and be the two models that the auto model picks from for me in the future. I also want a slider/dial to adjust at what point the auto model will swap from the light to heavy model.

This is require changes to the database schema, frontend, and the server

***

- [x] Fix price pie charts

When I go to my accounts page, the balance at the top of the page is correct (ie $16.74), but the two pie charts are incorrect.

For the Cost Breakdown pie chart, the amount for local inference shows $16.56, and Cloud inference shows $0.19, render $0.00. It should instead show local inferance at $0.19, cloud inference at $16.56, and render $0.00.

For the Top Cloud Models by Cost:
- Change it to instead just be 'Top Models by Cost' (ie Make it show the top cloud and local models)
- Currently, it shows one model, xiaomi/mimo-v2-omni at $2.63, which is far lower then it should be. It should be at around $16.56.
