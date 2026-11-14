# MediaFlow 6.1.0.565

**Advanced RPC mode:** modify MediaFlow's own Discord status, not just Custom Status.

Open it from **Settings → Discord → Modify MediaFlow's status…**.

- **Scenario:** choose a scenario, or **Every scenario**. There are 26: logging, title details, Library, History, Personal Order, a title shown with Consuming…, idle and the rest. Scenarios you've changed are marked "modified".
- **Starts from what Discord shows:** the fields open with MediaFlow's current status for that scenario already filled in, so you only change what you want.
- **Fields, like Custom Status:**
  - activity name, details, state, which line Discord shows, and activity type;
  - large and small image, with quick buttons for the title's cover or the MediaFlow logo, plus image texts;
  - links, where Discord's SDK supports them;
  - up to two buttons.
- **Stays live:** placeholders such as {title}, {progress}, {total} and {cover} keep updating. An empty field keeps MediaFlow's own value.
- **Preview** shows the result before you save.
- **Undo or reset:**
  - "Back to MediaFlow's status" removes one scenario's changes.
  - Turning Advanced RPC mode off shows MediaFlow's status again but keeps your changes for later.
- **Every device:** it's saved in your account.
