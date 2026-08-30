# Gotepad User Manual

[简体中文](user_manual.md) | [English](user_manual.en.md) | [日本語](user_manual.ja.md) | [한국어](user_manual.ko.md)

This manual applies to Gotepad 0.1.11. Gotepad is a cross-platform client for Go game recording, game review, branch organization, position notes and PPTX presentation export. The program is still in the development stage, and it is recommended to save a backup before making larger-scale game record modifications.

## Contents

- [Getting Started](#getting-started)
- [Interface Overview](#interface-overview)
- [Board Operations](#board-operations)
- [Playback and Navigation](#playback-and-navigation)
- [Branch Operations](#branch-operations)
- [Setup Stones](#setup-stones)
- [Variations](#variations)
- [Position Notes and Board Marks](#position-notes-and-board-marks)
- [Game Information](#game-information)
- [Saving and Loading SGF](#saving-and-loading-sgf)
- [Checking for Updates](#checking-for-updates)
- [Exporting PPTX](#exporting-pptx)
- [KataGo Analysis](#katago-analysis)
- [Settings](#settings)
- [Keyboard Shortcuts](#keyboard-shortcuts)

## Getting Started

After starting Gotepad, an empty board can be created or SGF game record can be loaded from a file or system clipboard.

### Create an Empty Board

1. Click "New" in the upper right corner, or press `Ctrl+N`.
2. Select a 9×9, 11×11, 13×13, 15×15, or 19×19 board.
3. Click Create.

Tags created directly are named "New Note" by default. When there is a tag with the same name, the program will append a number after the name.

### Create a Board from an Image

For the Windows version, you can select the board board size in the new interface and click "Select Local Pictures"; for the Android version, you can select "Photography" or "Album". The program can identify the current board position from real-life photos, Internet screenshots or book pictures, and first display the recognition and proofreading interface: for vertical pictures, you can first use "rotate clockwise" to expand the display area; drag the four yellow control points , align it with the four outermost intersections of board, and then click "Re-identify according to the current four corners"; click on any intersection to cyclically correct between empty points, black stones, and white stones. A red dot at the center marks a position where the program confidence level is low and it is recommended to focus on inspection. The stone mark will leave part of the edge of the original image to facilitate verification of the real stone below. After confirmation, the identified stone will be created as a setup stone node, and board will be locked by default.

Image recognition results will be affected by shooting angle, reflection, stone texture and screen cropping. Before creation, you should check the four corners, board board size and all red-dot positions; if the position does not comply with the basic Go rules, the program will reject the creation and require correction.

### Load SGF

After opening the new interface, you can click "Load" and select the local `.sgf` file; you can also copy the complete SGF text in other applications first, and then click "Paste" to directly create game record. game record created via the clipboard has no associated source file and needs to be selected when saving for the first time.

After loading successfully, board will roam to the last position of the first branch and be locked by default to avoid mistakenly move or undo when browsing game record. If the same SGF file is currently open, the program will not create tags again, but will activate the existing tags.

Windows distributions support receiving a `.sgf` file path in the startup parameters. Select Gotepad as the "open method" of SGF in the file explorer, or pass the SGF path to `Gotepad.exe` in the command line. The program will load game record directly after startup; when multiple SGFs are passed in at one time, labels will be created separately.

When there is an board tag, you can click `✕` in the upper right corner of the new interface or press `Esc` to close and return to the current game; if there is currently no board, the close button will not be displayed, and an board must be created or loaded.

## Interface Overview

- At the top is the game record tab bar. Click the label to switch game record, click `✕` on the label to close. A new note is automatically created after closing the last tab.
- On the left are board and game playback bars.
- Message and confirmation dialog boxes will automatically wrap according to the current window width, and the width will not exceed two-thirds of the window to prevent operation buttons from extending beyond the screen.
- On the right side of board are the operation buttons that automatically change columns according to the height of the window.
- Settings, New, Save, Save As, Export and Tools are provided in the upper right corner. The Tools menu centrally places less frequently used game record processing functions.
- Notes, game record information and KataGo use the same side panel area, and opening one of them will collapse the other panels.

The interface will automatically scale according to the actual vertical resolution of the window: 1.0x is used when the window height does not exceed 900 pixels, linear enlargement is between 900 and 2000 pixels, and 2.0x is used after reaching 2000 pixels. Fonts, buttons, icons, panels and pop-up windows will be enlarged simultaneously; the board camera will recalculate the remaining available space to ensure that board will not be cropped due to interface enlargement.

The desktop version will remember the position, size and maximized state of the normal window in `user://window_state.cfg` and restore it the next time it is started. After changing the monitor or changing the desktop layout, if the saved location is no longer within the available area of ​​any screen, the window will automatically return to the center of the home screen; the mobile version and the web version will not use this window state.

Commonly used icons are as follows:

| Icon | Function | Icon | Function |
|---|---|---|---|
| ![Undo](../gotepad-gd/assets/ui/undo.svg) | Undo | ![Redo](../gotepad-gd/assets/ui/redo.svg) | Redo |
| ![Forward find a stone](../gotepad-gd/assets/ui/find_previous.svg) | Towards game starting direction find a stone | ![Backwards find a stone](../gotepad-gd/assets/ui/find_next.svg) | Towards the end of game find a stone |
| ![Adjust branch](../gotepad-gd/assets/ui/reorder_branch.svg) | Adjust the order or delete a branch | ![variation](../gotepad-gd/assets/ui/variation.svg) | Enter variation |
| ![Branch browsing](../gotepad-gd/assets/ui/branch_visualization.svg) | Branch visualization | ![Notes](../gotepad-gd/assets/ui/notes.svg) | position notes |
| ![game recordinfo](../gotepad-gd/assets/ui/sgf_info.svg) | game recordinfo | ![KataGo](../gotepad-gd/assets/ui/katago.svg) | KataGo analysis |
| ![human-like play](../gotepad-gd/assets/ui/katago_human_play.svg) | KataGo Human-like Play | ![endgame scoring](../gotepad-gd/assets/ui/territory_scoring.svg) | endgame scoring |
| ![Preset branch](../gotepad-gd/assets/ui/setup_branch.svg) | Select branch setup stones | | |

## Board Operations

### Playing a Move

- boardWhen it is not locked, you can move click the left mouse button on the legal intersection.
- A semi-transparent preview will be displayed when the mouse is hovering over the available location.
- Use the black and white stone switch button or `Ctrl+Q` to specify the next color. After normal move, black and white alternation will be restored by default.

After enabling "Move confirmation", the first click on a legal intersection will only display a translucent stone to be confirmed, and game record will not be modified immediately. The green `✓` at the top of the toolbar on the right of board is used to confirm move, and the red `✕` Used for cancellation; click on other legal intersections before confirmation to move the pending stone, and right-click the mouse to cancel. Entering the existing next branch will still roam directly without confirmation. This feature is turned off by default on the desktop version and enabled by default on mobile versions such as Android and iOS. User-saved settings take precedence over platform defaults.
- The program abides by basic rules and does not accept illegal events such as suicide.

board will mark all the next move branches that can be entered with translucent graphics: the next hand on the current play path uses a square, and other branches use circles. When clicking on a marker:

- If the currently selected color is the same as the existing branch move, this branch will be entered.
- If the currently selected color is opposite to the existing branch move, a new branch of the selected color will be created at the same location.
- You can still enter the branch by clicking on the box in the locked state, and no new move will be created.

### Taking Back Moves, Undo, and Redo

- When board is not locked, right-click the mouse to request undo. After confirmation, the current last step will be cut.
- When board is locked, the right mouse button changes to roam to the previous position, without modifying game record.
- undo is an game record editing command and is not equivalent to Undo.
- `Ctrl+Z` undoes the most recent undoable command, `Ctrl+R` redoes it. Locking does not prevent Undo/Redo of roaming commands.
- When the icon has a slash, it means that the corresponding Undo or Redo cannot be executed currently.

### Board Lock

After checking the board lock or pressing `Ctrl+E`, move and undo are prohibited, but still allowed:

- Use the play bar, mouse wheel, and arrow keys to browse game;
- Click on the next branch mark;
- Use functions such as find a stone and branch browsing that are not directly move;
- Perform Undo/Redo on roaming operations.

Lock board is enabled by default after loading SGF.

## Playback and Navigation

The play bar below board indicates the current position in the linear game path.

- Drag or click the play bar to jump.
-Hovering the mouse on the play bar will display the corresponding number move number.
- Click `<`, `>` to browse forward or backward with one hand.
- When the mouse is on board, the scroll wheel moves backward upward and forward downward.
- Keyboard `←`, `→` are global single-step browsing keys; the keys will not be preempted when the text box or list is being edited.
- Click the play button to automatically advance according to the set interval; click the stop icon again or press `Esc` to stop.
- During playback, as long as the user changes the progress using the play bar, scroll wheel, direction keys, etc., the automatic playback will stop.
- The Android version also makes the forward `>` and backward `<` hand-by-hand into two large square buttons in the lower right corner of the screen for easy touch control; from top to bottom, they are forward and backward. The original small hand-by-hand buttons in the playback bar are still retained.

For game record with multiple branches, the play bar only represents the currently selected linear path, which is not equivalent to the entire game record tree.

## Branch Operations

### Keep the Main Line

Click "Tools" in the upper right corner and select "Keep main line" to delete all side branches in game record and only keep the path starting from the starting point of game and selecting the first branch at each layer until the final leaf node. The program will ask for confirmation before execution; the entire pruning is entered into the history as a command, so only one Undo can restore all deleted branches and the position where it was before the operation.

### Find a Stone

![Start direction game towards find a stone](../gotepad-gd/assets/ui/find_previous.svg)

![Toward game end direction find a stone](../gotepad-gd/assets/ui/find_next.svg)

1. Click the forward or backward find a stone icon, or press `Ctrl+G` or `Ctrl+F` respectively.
2. Move the mouse to the target intersection or stone to confirm the position of the opaque magnifying glass.
3. Left-click, the program will search for the position that last changed the position in the specified direction.

If it is not found, it will immediately exit the find a stone mode and prompt. Press `Esc` or right mouse button to cancel find a stone.

### Adjust or delete the next branch

![Reorder branch](../gotepad-gd/assets/ui/reorder_branch.svg)

The button is available when the current position has at least one sub-branch, which can also be opened by pressing `Ctrl+X`. Both the move branch and the setup stones branch will be listed:

- Use the `↑` and `↓` on both sides of each line to adjust the order, and click the green `✓` at the top of the panel to write the results;
- Double-click the board thumbnail of the branch or click the "Enter" button on the right side of the thumbnail to roam directly into the branch. The panel will then display the next branch of the new position; sequence adjustments that have not been confirmed before entering will be abandoned;
- Click the red `✕` at the end of the line to confirm and delete the branch and all subsequent nodes;
- Click the red `✕` at the top of the panel or press `Esc` to abandon uncommitted sequence adjustments.

Confirmed branch deletion is performed immediately and can be reversed with Undo; it is not affected by whether the reordering is subsequently abandoned. Please note that branches restored through Undo will return to the end of the branch sequence and will not automatically return to their original positions.

### Setup Stone Branches

![setup stones branch](../gotepad-gd/assets/ui/setup_branch.svg)

In the next step, when there are setup stone branches that cannot be expressed by a single move box, a button with a quantity prompt will appear at the top of the toolbar. After clicking, you can view the board changes caused by each branch and choose to enter the target branch.

### Branch Visualization

![Branch Visualization](../gotepad-gd/assets/ui/branch_visualization.svg)

Click the icon or press `Ctrl+W` to open the game record tree view. The view will include branch key nodes, nodes with notes, and leaf nodes of each branch. The progress will be displayed when a large game record is generated for the first time; the generated thumbnails will be cached by game record and UID.

-Scroll wheel to zoom the view.
- Hold down the right mouse button and drag the canvas.
- On Android touch screen devices, pinch with two fingers to zoom in and out of the view, and slide with two fingers to move the canvas; dragging with one finger from an empty area that does not hit the board thumbnail or button can also move the canvas.
- Left click on the thumbnail to select position.
- Click the green `✓` in the upper left corner of the check box, or double-click the selected thumbnail to navigate to the position and exit the view.
- Click the red `✕` in the upper right corner of the check box and confirm to delete position and all subsequent branches.
- Click "Exit" in the upper right corner or press `Esc` to close the view.

The title of the first-level note will be displayed above the thumbnail; if a comment exists, a semicolon will be used to connect the first line of the comment after the title. If the title is empty, only the first line of the comment will be displayed. Comments will be preceded by notebook markers. The title can display up to two lines. When it is a single line, it will be close to board. If the content is too long, it will be truncated at the width of board.

## Setup Stones

Click "Preset" on the left side of the playback bar, or press `Ctrl+H` to enter preset mode. After entering, the regular buttons except black and white color switching will be temporarily hidden.

- Left click on the intersection to set the current color to setup stones.
- Right-click to clear the intersection; you can also click the `⌫` button on the right to enter the clear state, and then click on the intersection to be cleared.
- The preset mode provides black, white and `⌫` cleaning tools respectively. Click which one to activate; the cleaning tool will display gold when activated. You can also press `Ctrl+Q` to switch between black and white. The color will not change automatically after presetting move.
- Click the green `✓` to submit all modifications as a preset node.
- Click the red `✕` or press `Esc` to abandon this modification.

The final disk after presetting must still comply with basic rules such as stone chainhas liberties. When the current position does not allow preset, the entrance will display an unavailable status.

## Variations

![variation](../gotepad-gd/assets/ui/variation.svg)

Click the variation icon or press `Ctrl+T`, and the program will copy the current board position to a temporary game record. variation is suitable for trying, and the main game record will not be modified immediately.

- The original next hand color will be inherited when entering, and then the default color will alternate between black and white.
- You can use the play bar, `<`, `>`, or scroll the mouse wheel on board and the play bar to browse the change process that has been downloaded; the wheel goes back upwards and forwards downwards, consistent with the normal game mode.
- When browsing to the middle position, you cannot continue to move. You must first go back to the end of variation.
- Allowed at the end or midway undo, you can use the right mouse button or the `↩` button on the right and will ask for confirmation.
- Green `✓` means adding the new move to the main game record one by one and then exiting.
- Red `✕` or `Esc` means discard changes and exit.

When entering from KataGo candidate variation, the candidate sequence is automatically filled in with temporary game record. After exiting variation, the side panel opened before entering will be restored.

## Position Notes and Board Marks

![Notes](../gotepad-gd/assets/ui/notes.svg)

Click the note icon or press `Ctrl+M` to open the notes panel. The same position can have multiple layers of notes:

- Click `+` to add a layer of notes, numbered starting from 0.
- Only the last layer of notes with the highest number can be closed to avoid misalignment of intermediate numbers.
- Note No. 0 is saved in the current move or preset node; subsequent notes are saved in independent nodes in SGF.

Notes at each level include node titles, comments, board marks and move numbering methods. When a title or comment changes, use the green `✓` next to it to accept or the red `✕` to discard it. Pressing `Esc` during editing will cancel editing and release the input focus; when clicking other controls with unconfirmed content, the program will ask whether to retain it.

"Focus" on the right side of the move numbering option can enter the preview mode of the entire game record note. The preview page is arranged in the order of the game record tree exported by PPTX, and the multi-layered notes of the same position are displayed in order according to the tag number; when there are notes in the current position, it starts from the selected note, when there are no notes, it is first positioned to the nearest note in the back, and then to the front when the back does not exist. During the preview, the play bar below board is used to jump between notes, `<`, `>` are used to change pages in a single step, and the play button automatically changes pages according to the playback interval in the settings; the large page change button in the lower right corner of the Android version also remains available. The note panel maintains complete editing functions. The label at the top is only used to indicate the current note layer. The playback controls are used uniformly for page changes. The "Focus" button will change to "Exit" and return to the normal note mode after clicking it. You cannot enter the preview when there are no notes in game record.

The Android version provides "select all, copy, cut, paste" touch buttons in the note title and comment editing area. First place the cursor in the text box or select part of the text, and then click the corresponding button to exchange text with the Android system clipboard; desktop versions such as Windows continue to use system shortcut keys and right-click menus, and do not display this row of buttons.

When you need to remove the entire game record notes, you can click "Tools" in the upper right corner and select "Clear Notes". After confirmation, all position titles, comments, move numbering methods and board marks will be cleared; the entire operation only takes up one history step and can be fully restored through an Undo.

### Board Marks

- `ABC`: Add letter marks in the order of A-Z, a-z.
- `TR`: triangle mark.
- `SQ`: box mark.
- `CR`: circle mark.
- `MA`: cross mark.
- Trash: erase mark.

After entering mark mode, other interfaces are temporarily hidden. The left click can add or switch marks on the empty intersection or stone; use the green `✓` on the right to submit, the red `✕` or `Esc` to give up. Use a light color for the markings on black stones, and a dark color for the markings on the intersections of white stones and empty stones.

### Move Numbering

The numbering method is mainly used for PPTX typesetting:

- **Branch relative numbering**: Renumber from 1 after the previous layout object node.
- **Branch Absolute Numbering**: Only mark move from the previous layout object node to the current position, but the numbering uses the actual move number of that move in the current branch.
- **Global Absolute Numbering**: Starting from the starting point of game, use the actual move number for all move in the current path.
- **Unnumbered**: The exported board does not display move numbering.

When there are multiple moves at the same intersection, the export will display the smallest number first, and explain the correspondence between this number and subsequent numbers below board.

When the notes panel is open and there are notes in the current position, board will be given priority to be displayed according to the numbering method selected on the current note tab, temporarily overriding the regular move number display options in the settings panel. It will be updated synchronously after switching note tags or roaming to other position with notes; when the current position has no notes and only displays the `+` tag, the normal settings will be used. The normal settings will also be restored after closing the note panel.

## Game Information

![game recordinfo](../gotepad-gd/assets/ui/sgf_info.svg)

The game record information panel can edit the game name, event, round, date, location, black and white names and rank, results, rules, komi, handicap number, time, countdown, layout name, recorder, source, copyright and game general rating and other commonly used SGF header information.

After modification, click the green `✓` at the top of the panel to submit all fields at once, and click the red `✕` to give up. When editing content loses focus, it will also ask whether to keep it. Fields such as date, komi, handicap number, time and result should follow the interface example format, otherwise they may be rejected by the SGF validator when saving.

## Saving and Loading SGF

- Click "Save" or press `Ctrl+S`, confirm the path and save the current game record.
- Click "Save" or press `Ctrl+A` to select the new file.
- The successful saving prompt can be closed with space, enter or `Esc`.
- Closing a tag currently only confirms whether it is closed, and has not yet implemented complete "unsaved modifications" status detection. Please develop the habit of proactively saving.

The program only allows one file picker when loading, saving, exporting or selecting KataGo files. If the native file selector is obscured by Gotepad's main window, clicking the corresponding file selection button again will bring the already open selector back to the foreground without creating a second one.

Gotepad will read and write path numbers, legal files, branches, AB/AW/AE preset operations, titles, comments, common tags, and main password information. The program also writes Gotepad custom properties such as `AP[Gotepad:Version]`, `GP`, `XU` and `XN`, which are used to save the format version, position UID and note numbering method.

When saving SGF, Gotepad will take protective measures to try to avoid writing failure and damaging the original file. Important game record It is still recommended to use "Save As" regularly to create independent backups.

Note:

- It is not recommended to use a text editor to modify Gotepad custom properties at will, otherwise the reload may fail due to UID conflicts or type errors.
- For SGFs not generated by Gotepad, the program will not blindly trust these custom properties, but will verify or ignore values ​​that do not meet the range.
- Illegal move will not be imported. The pass in SGF is not managed as an board state node, but will be generated as required by game record when saved.
- External SGF software may not fully retain Gotepad's custom data such as multi-layer note numbers; it is recommended to retain the original files before exchanging across software.

## Checking for Updates

Click **Update** below **Tools** on the far right of the interface. Gotepad connects to GitHub and checks for a newer version applicable to the current platform. When the check finishes, the window shows the current version, the newest available version, and notes for up to the five newest applicable versions in that range, ordered from newest to oldest. If a historical version has no separate GitHub Release, Gotepad attempts to use the version commit associated with its Tag. Releases prefixed for other platforms are ignored. If the current version is already the latest and its corresponding GitHub Release still exists, the window also shows that version's release notes.

Choose **GitHub** or **Cloud drive** in the upper-right corner, then click **Update** to open the corresponding download page in the system's default browser. Gotepad only checks for updates and opens the page; it does not download or install updates inside the application. If GitHub cannot be reached, the result window still displays the error and the Cloud drive link remains available.

## Exporting PPTX

Click "Export" in the upper right corner and select `.pptx` to save the location. Export using the B5 landscape template, and the following content will become the layout page:

- All position with notes;
- Each layer of notes of the same position;
- Force export of all branch leaf nodes even if there are no notes.

board uses a black and white publication style and draws notes designated move numbering, sequential letters, and TR/SQ/CR/MA graphic marks. Titles, comments, figure titles, and descriptions of repeated move numbers will be written in the layout.

"Export board coordinates (left and upper sides)" in the settings can control whether the exported board has coordinates. After enabling, only the column letters are drawn on the upper side of board and the row numbers are drawn on the left side; the coordinates will be close to board and avoid the edge stone to minimize the additional space occupied. This option is off by default and applies to both SVG and PNG exports.

### SVG or PNG

Select the format in "Settings → PPTX Board Image":

| Format | Advantages | Notes |
|---|---|---|
| SVG (default) | Vectors are clear, have the best enlargement and printing quality, and generally have smaller file sizes | Some older versions of PowerPoint, WPS, or compatible software may not display embedded SVG |
| PNG | Can be displayed stably in more presentation software | board is generated at 1600×1600 pixels, the file is usually larger, and extreme enlargement is not as clear as SVG |

If the exported file is mainly used in the new version of PowerPoint or for high-quality printing, give priority to SVG; if it needs to be sent to users with unknown environments, or if you have encountered the problem that the board image is not displayed, choose PNG.

### Font

The board number in PPTX has been rasterized in PNG mode, but the title and comments are still editable text. Currently exported files do not embed fonts, it is recommended to install the Noto Sans CJK SC and Noto Serif CJK SC fonts included with the project on your editing or printing computer.

If the fonts are not installed, PowerPoint will replace them, possibly causing line breaks or layout changes.

## KataGo Analysis

![KataGo Analysis](../gotepad-gd/assets/ui/katago.svg)

The desktop version of Gotepad does not distribute the KataGo executable and neural network models with the software. You need to specify in the settings before use:

1. KataGo Analysis Engine executable file;
2. A neural network model compatible with this version (usually `.bin.gz`);
3. `.cfg` configuration file used by Analysis Engine.

After the settings are completed, click "Test Path". You can also run "automatic performance detection" to let the program estimate the number of search threads and batch size; the first initialization of backends such as TensorRT may take a long time, and the detection does not set a fixed time limit. You can view the real-time output of automatic line wrapping in the modal window that accounts for about 80% of the current window and actively stop it. After the test is successful, close the result window and use the green `✓` in the upper left corner of the settings panel to confirm saving the test results; other settings will be temporarily disabled during the test.

### Analyze the Current Position

After opening the KataGo panel:

- The play button starts the current position analysis, and the results are updated according to the set refresh interval.
- The pause button only pauses the interface refresh, KataGo continues to calculate; when resuming, the latest results are displayed.
- The Stop button sends a request to the engine to terminate the current analysis.
- "Increase the amount of calculation" reanalyzes the current position according to the `maxplayouts` specified in the input box on the right. The value must be greater than 0; you can still pause the interface refresh or stop the analysis during operation.
- After checking "Continuous Analysis", roaming to the new position will automatically re-analyze; at this time, the play, pause and stop buttons are taken over by the continuous mode.

The candidate table shows the location, current move entrances win rate, score lead and variation. The top three candidates will be marked on board with translucent dark green, light green and yellow; the "Extra Board Candidates" in the settings can display 0 to 99 more candidates. The additional candidates will uniformly use a lighter yellow with a transparency of 20% to reduce the impact on the observation of stone. If the candidate position coincides with the real next move along the current play path in game record, a thin black frame will be added to the candidate, and the same will be displayed when additional candidates hit. When the entire play path has been analyzed, if the actual next move of game record is not among the top three, and the analyzed move square win rate is at least 10 percentage points lower than the first choice, the program will display the negative win rate difference with a light red circle in the actual next move position. Clicking "Enter" in the table will load the candidate sequence into variation; when board is locked, you can also directly click on the candidate marker on the board to enter the corresponding variation, and then you can choose to keep or discard it.

### Analyze the Entire Playback Path

Click "Analyze the entire playback path" and the program will use the "calculation amount" to generate win rate and score lead curves one by one. This value is low by default and is intended to quickly observe trends and should not be taken as a precise research conclusion. The vertical line in the curve represents the current position; click elsewhere on the curve to roam there.

KataGo's win rate and score lead are affected by rules, komi, model, calculation amount and hardware. The results of low visits fluctuate greatly, and important conclusions should be reviewed with more calculations. The desktop version uses an external KataGo engine configured by the user; the Android version gives priority to using the OpenCL GPU backend provided by the device, and automatically switches to the more compatible Eigen CPU backend when the device does not support OpenCL or the backend fails to start; the iOS version still does not run local KataGo.

### Human-like Play

![human-like play](../gotepad-gd/assets/ui/katago_human_play.svg)

Click the human-like play icon below the normal KataGo icon to start with the Human SL model game from the current board position. Before starting, you can choose whether the AI ​​plays black or white, modern or pre-AlphaGo playing style, simulates playing strength, and the AI ​​calculation amount per hand; the calculation amount input box will display the current visits value in the "Human-like Play Visits" setting, and the temporary adjustment in the dialog box will only take effect for this game. Lower values ​​are faster, but have fewer human candidates for the master model to evaluate, making significant mistakes more likely; raising the value more fully suppresses candidates with excessive losses while still retaining the selected humans. The program will retain the current board position, so the middle position that already has game record can be handed over to AI to take over.

After entering the human-like play mode, the KataGo analysis panel will automatically open. Human-like play uses temporary game record, the progress bar and regular board tools will be temporarily hidden, and only KataGo analysis, endgame scoring, undo, keep and give up buttons will be retained. The current position operation, candidate table and quick whole-game analysis button in the lower right corner of the analysis panel are all inoperable, but the win rate and score lead curves will continue to update with the game results. In the human round, you can use the undo button to undo the previous human move and subsequent AI moves at once; the AI ​​cannot undo during the thinking period. After exiting the mode, the analysis panel returns to the open or closed state it was in before entering.

The status message of the analysis panel will be prefixed with the current Human SL gear, for example `[rank_1d] The AI ​​is thinking...`. `rank_` represents the modern playing style, `preaz_` represents the playing style before AlphaGo appeared, and the second half is the playing strength selected by this game.

When AI selects pass, the program will ask the user whether to also pass and does not provide an independent pass button. After choosing to continue move, you can still continue playing on the board; both parties can use endgame scoring to check the results after pass. After clicking the green `✓`, the program will prompt that this operation will end game and record the game process step by step to the original game record, and then execute it after confirmation; the red `✕` or `Esc` will abandon this game record after confirmation.

### Endgame Scoring

![endgame scoring](../gotepad-gd/assets/ui/territory_scoring.svg)

endgame scoring currently only supports Chinese rules. All dame points should be completed before use, and then click the endgame scoring icon at the end of the toolbar on the right side of board. The program will call KataGo to determine the black and white of each intersection, and cover board with translucent region markers; green `✓`, red `✕`. The independent log panel on the right will display engine startup information and real-time determination progress line by line like a command line.

KataGo's life and death and region determination may be wrong. When an error is found, clicking on the corresponding intersection will switch the entire area connected to it in four directions to the other side; after confirming all the marks, click the green `✓`, and the program will remove the stone that is judged to be dead, perform regional divisions on the remaining empty points, and list the total black and white, komi, and winning and losing numbers according to the Chinese rules of "stone + empty points". Red `✕` or `Esc` will exit directly without modifying game record. The endgame scoring results are only for auxiliary verification. Complex life and death, seki and unfinished dame points should still be reviewed by the user.

## Settings

Click "Settings" in the upper right corner or press `Ctrl+O`. After modifying the settings, the upper left corner of the panel will appear: green `✓` to save, blue `↺` to restore the original modification, and red `✕` to cancel and close.

### Interface language

"Interface language" can be selected from Chinese, Japanese, 한국어 or English. After switching options, the interface will immediately preview the selected language; click the green `✓` to write the settings and continue to use them at the next startup. Click the blue `↺`, red `✕` or directly close the settings panel to restore the language when the settings were opened. Program buttons, prompts, tooltips, and core command messages numbered with `[GNE…]` will switch with the language; game record titles, notes, file names, KataGo raw logs, and the contents of the SGF file itself will not be automatically translated. The native file picker provided by the desktop system uses the operating system language and is not controlled by Gotepad's interface language.

### Appearance and playback

- board Texture: Toggle light or dark wood grain.
- stone Texture: Switch glossy or matte black and white stone.
- Screen left and right margins (for mobile): In pixels, keep board, tab bars, buttons and panels away from the left and right edges of the screen at the same time, and apply them symmetrically; the default is `0 px`. On landscape devices with rounded corners or cutouts, you can gradually increase this value until the control is fully visible. The background texture will still fill the entire screen.
- board horizontal width ratio: Limit board to use the maximum proportion of the original available horizontal space. The allowed range is `50%~100%`, and the default is `100%`. On screens with tight horizontal space such as `4:3`, you can adjust it appropriately to reserve more space for notes and the KataGo analysis panel; board will still be fully displayed without cutting off the edges.
- Large UI (for mobile terminals): When enabled, the current interface magnification calculated linearly with the window height is multiplied by the specified magnification on the right. The default is `1.5` times, which is convenient for touch operations on mobile phones and tablets. The allowed setting range is `0.7~2.0`, and values ​​outside the range will not take effect. This option also appears and is available on desktop.
- Display move number: Display the latest 1 lot, 10 hands, all move number or a custom quantity.
- Absolute move number: Use absolute movemove number from the current branch, otherwise show relative numbering.
- Playback interval: the number of seconds to wait for each step of automatic playback, the default is 1 second.
- move Sound effect: Use the 0–100 slider to adjust, the default is 50, and it is muted when set to 0. The program will randomly play five real Gomove recordings; it will be played when a new move is successfully created and roaming to the next move node. Loading game record, roaming to the preset node and setup stones will not be triggered.
- Move confirmation: first display the semi-transparent stone for confirmation, click the green `✓` to actually move; it is turned off by default on the desktop and enabled by default on the mobile terminal.
- PPTX Board Image: Switch between SVG and PNG, default is SVG.
- Export board coordinates: Display column letters on the upper side of PPTX board and row numbers on the left. The default is off.

### KataGo

- Analysis calculation amount: `maxVisits` currently analyzed by position, default 500.
- Analysis refresh interval: the interval for receiving phased results, the default is 2 seconds.
- Candidate variationmove number: The maximum number of candidate PVs displayed is move number, and the default is 10.
- Number of additional board candidates: The number of board candidates displayed in addition to the top three candidates, ranging from 0 to 99, with the default value being 0.
- Display score lead: Controls whether candidate tables and curves display score lead.
- quick whole-game analysis Calculation amount: Analyze visits used position one by one, default 1, priority is given to speed.
- Test path: Check if executables, models and configurations can be launched.
- Automatic performance detection: Continue running until KataGo completes the detection or the user actively stops it to estimate the appropriate parameters of the current device; benchmark output will be displayed in the modal window during running.

When opening the settings, if the saved KataGo path becomes invalid, the interface will clear the path and require you to select it again. Automatically generated performance configurations are saved in Godot's user data directory and are not written to the installation directory to accommodate permission differences on Windows, Linux, and macOS.

"KataGo Human-like Play" is an independent setting area. The desktop version needs to select the Human SL `.bin.gz` model that is compatible with the current KataGo executable file; the Android version imports the model through the system file selector, and the imported file is managed by the application. Human SL models cannot be replaced by ordinary analytical models. The "human-like play visits" here is not only the default visits of the new game, but also the actual load used by the automatic performance detection; after modifying it, the performance detection in this area should be re-executed. This detection will generate a separate configuration for human-like play, and the detection results of the ordinary analysis model will not be directly reused.

When starting the human-like play performance test, the program will first check the model path in the settings panel. If the path has not been saved, or is different from the currently valid path, the program will ask whether to save the path first and continue; after confirmation, it will also check whether the file actually exists, can be read, and the format is supported. If the check fails, you need to reselect a valid model. The confirmation here is only responsible for making the selected model path take effect; after the performance test is successful, you still need to click the green `✓` in the upper left corner of the settings panel to save the newly generated performance configuration.

## Keyboard Shortcuts

| Shortcut keys | Functions |
|---|---|
| `Ctrl+N` | Create new game label |
| `Ctrl+S` | Save SGF |
| `Ctrl+A` | SGF Save As |
| `Ctrl+O` | Turn settings on or off |
| `Ctrl+Z` | Undo |
| `Ctrl+R` | Redo |
| `Ctrl+G` | Start direction find a stone towards game |
| `Ctrl+F` | Towards the end of game find a stone |
| `Ctrl+X` | Open the next branch sequence and deletion panel |
| `Ctrl+E` | Switch board lock |
| `Ctrl+Q` | Switch to black and white color of next hand |
| `Ctrl+H` | Enter setup stones mode |
| `Ctrl+T` | Enter variation |
| `Ctrl+M` | Open or close the notes panel |
| `Ctrl+W` | Open branch visualization view |
| `←` / `→` | Go back or forward one hand along the playback path |
| `Esc` | Cancel the current mode, stop playing or close the current temporary interface, the specific behavior changes with the context |

Shortcut keys will not be triggered when text input boxes such as titles and comments receive focus. Press `Esc` first to end or cancel text editing, and then use global shortcut keys. `Ctrl+A` and `Ctrl+W` are "save as" and "branch visualization" respectively in Gotepad, which are different from the default meanings of some common software.

## Android Version

The current version of Android supports arm64-v8a devices with Android 9 and higher, and is designed for landscape use. Copy the APK file to the device to install it; if the system blocks installation, you need to follow the system prompts to allow the application to be installed from that source.

The Android version has built-in KataGo OpenCL/Eigen analysis backend, model and internally managed configuration files, without the need to select executable files or configuration paths. The model currently built into the APK is `g170e-b10c128-s1141046784-d204142634`, which belongs to the 10 block / 128 channel network of KataGo g170 extended training. Thanks to Jane Street and KataGo author David J. Wu (lightvector) for contributing computing power and data to the g170 training batch, and for contributing relevant model data to the public domain under CC0; also thanks to the pachi project for providing the download image of the model. The "Neural Network Model" in the settings uses the built-in model by default; you can also click "Browse" to import standard KataGo `.bin.gz` or `.txt.gz` weights through the Android system file selector. The import process will copy the model to Gotepad's application data directory, so subsequent movement or deletion of the original file will not affect use; please confirm that the device has sufficient storage space and running memory before importing large models. The dual-file Android optimization model used by software such as BadukAI is not a standard KataGo weight and cannot be loaded directly here. Click "Built-in" and save with green `✓` to switch back to the model provided with the software. The program will give priority to using the OpenCL GPU backend exposed by the device; if the device does not have an available OpenCL implementation, the driver initialization fails, or the independent analysis process exits abnormally, it will automatically fall back to the Eigen CPU backend. Options such as analysis calculation amount, refresh interval, candidate variationmove number, score lead display and quick whole-game analysis calculation amount can still be adjusted, and automatic performance detection can also be run; the detection results need to be confirmed with the green `✓` in the upper left corner of the settings panel before they are written to the internal configuration. The OpenCL backend needs to be tuned for the current GPU when running it for the first time or when changing models, and therefore may be significantly slower than subsequent launches. Analysis will increase power consumption and heat generation. It is recommended to pay attention to the device temperature when analyzing for a long time.

The Android version can load SGF through the system file selector, or paste the complete SGF text from the system clipboard; Chinese, Japanese, Korean and other file names and game record content can be displayed normally.

Android file managers or other applications that support system "open with" can open SGF directly using Gotepad. When the application is not running, it will start and load game record. When the application is already running, it will be opened in a new tab; the same game record that is already open will be switched to the existing tab. Files provided by external applications may only have read permissions. In this case, "Save" on the toolbar will automatically change to select a new location to save, and no attempt will be made to overwrite the read-only source.

When saving, saving as SGF, or exporting PPTX on Android, please wait for the success or failure prompt to appear before closing the program. If the original file cannot be overwritten directly, please use "Save As" to select another location.

The Android side currently does not support PPTX export in PNG mode. Please select SVG mode in the settings. The SVG image version of PPTX can be viewed and edited using Microsoft's official PowerPoint App; WPS may not be able to display the SVG image in it.

## Data Locations and Usage Recommendations

- Settings and KataGo automatic performance configurations are saved in the current system user's application data directory.
- SGF and PPTX are saved in the user's own choice and will not be automatically saved in `user://`.
- The current version does not have a complete unsaved status prompt and automatic recovery mechanism. You should actively save before closing the tab or program.
- Before cutting branches in batches, editing game record information, or adjusting a large number of notes, it is recommended to "save" as a backup file first.
- When cross-software exchange is required, give priority to retaining a copy of Gotepad's original SGF to prevent other software from discarding custom attributes.
- When used for printing or presentation delivery, the fonts, board pictures and paging effects should be checked on the target computer; the desktop version can be exported using PNG when compatibility is uncertain.
- KataGo analysis will continue to use CPU/GPU. Analysis can be stopped during light operations such as note editing to reduce power consumption and device temperature.
