package {
    import flash.display.*;
    import flash.events.*;
    import fl.containers.ScrollPane;
    import fl.controls.ScrollPolicy;
    import fl.controls.Button;
    import flash.utils.Timer;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.geom.Point;

    import flash.net.URLLoader;
    import flash.net.URLRequest;

    import com.adobe.serialization.json.*;

    import scaleform.clik.controls.TextInput;
    import scaleform.clik.events.FocusHandlerEvent;

    import ValveLib.Globals;
    import ValveLib.ResizeManager;

    public class frota extends MovieClip {
        // Game API related stuff
        public var gameAPI:Object;
        public var globals:Object;
        public var elementName:String;

        // These vars determain how much of the stage we can use
        // They are updated as the stage size changes
        public var maxStageWidth:Number = 1366;
        public var maxStageHeight:Number = 768;

        // Amount of space to leave under the bottom
        public var bottomMargin:Number = 90;

        // Sizing
        public var iconWidth:Number = 64;
        public var iconHeight:Number = 80;
        public var iconHeightX:Number = 64;
        public var voteHeight:Number = 31;
        public var iconMiniSize:Number = 16;
        public var avatarSize:Number = 64;
        public var heroIconWidth:Number = 64;
        public var heroIconHeight:Number = 49;
        public var heroIconHeightX:Number = 36; // Height of the icon (not including the text)

        // Limits
        public var maxSkills = 4;

        // Side bar setting
        private var sidePaddingX = 1;
        private var sidePaddingY = 4;
        private var sideTotalWidth = (iconMiniSize+sidePaddingX) * (maxSkills+2) + 128/4.5 + sidePaddingX*2;

        // Main panel stuff
        private var contentPanelHolder:ScrollPane;
        private var contentPanel:MovieClip;

        // This contains the currently selected skill (will probably be removed)
        private var selectedSkill:MovieClip;

        // This is the red mask thingo (for lining stuff up)
        public var hudMask:MovieClip;

        // Hides the game
        public var hideGame:MovieClip;

        // This holds vote panels (so we can update them)
        private var voteHolder:Object;

        // Contains picking data
        private var pickingData:Object = {};

        // State control
        private var currentState:Number = 0;
        private var gottenInitialState = false;
        public static var STATE_INIT = 0;
        public static var STATE_VOTING = 1;
        public static var STATE_PICKING = 2;
        public static var STATE_BANNING = 3;
        public static var STATE_PLAYING = 4;

        // Tab control
        public static var TAB_NONE = 0
        public static var TAB_SKILL_PICKER = 1;
        public static var TAB_HERO_PICKER = 2;
        public static var TAB_SKILL_BANNER = 3;

        // Drag sorts
        public static var DRAG_SORT_SKILL = 1;
        public static var DRAG_SORT_HERO = 2;

        // This is for toggling input on text fields
        private var bGotInput = false;

        // This will contain movieclips and stuff that needs to be cleaned up
        private var stateCleanup = new Array(); // Generic stuff that can be removed
        private var stateCleanupSpecial = {};   // Specific things that can be removed

        // Shortcut functions
        public static var Translate;  // Translates a #tag into something readable

        // Contains the movieclip we are dragging
        public var dragClip;
        public var dragClickedClip;
        public var dragTarget;
        public var dragSort;

        // An array of steamIDs, index = playerID
        public var steamIDs = [];

        // An object to store timers
        public var serverTimers = {};

        // Stores the last state data
        public var lastStateData;

        // Update related
        public var lastUpdate = 0;
        public var lastUpdateCheck = 0;

        // Current picker tab
        private var currentPickerTab = TAB_SKILL_PICKER;

        public function frota() {}

        public function onLoaded() : void {
            // Store shortcut functions
            Translate = Globals.instance.GameInterface.Translate;

            trace("\n\n-- Frota hud starting to load! --\n\n");

            // Allow people to see
            hideGame.visible = false;

            //trace('globals:');
            //PrintTable(globals, 1);

            this.gameAPI.SubscribeToGameEvent("hero_picker_hidden", this.requestCurrentState);
            this.gameAPI.SubscribeToGameEvent("afs_initial_state", this.receiveInitialState);
            this.gameAPI.SubscribeToGameEvent("afs_update_state", this.processState);
            this.gameAPI.SubscribeToGameEvent("afs_vote_status", this.updateVoteStatus);
            this.gameAPI.SubscribeToGameEvent("afs_update_builds", this.updateBuildDataHook);
            this.gameAPI.SubscribeToGameEvent("afs_steam_ids", this.updateSteamIDs);
            this.gameAPI.SubscribeToGameEvent("afs_timer_update", this.updateTimersHook);
            this.gameAPI.SubscribeToGameEvent("afs_score_update", this.updateScoreHook);

            // Hide the Hud Mask
            hudMask.visible = false;

            // Make the hud visible
            visible = true

            // Request the current state
            requestCurrentState();

            // Hook stuff
            Globals.instance.resizeManager.AddListener(this);
            this.gameAPI.OnReady();
            Globals.instance.GameInterface.AddMouseInputConsumer();

            // Update checker (the hud can be disabled, and miss events, this fixes that)
            lastUpdateCheck = this.globals.Game.Time();
            var timer:Timer = new Timer(1000);
            timer.addEventListener(TimerEvent.TIMER, function(e:TimerEvent) {
                // Check if too much time has passed
                if(globals.Game.Time() - lastUpdateCheck > 2) {
                    requestCurrentStateInsant();
                }

                // Update when we last checked for updates
                lastUpdateCheck = globals.Game.Time();
            });
            timer.start();


            // Text input
            /*var a = new DefaultTextInput();
            addChild(a);
            a.x = 4;
            a.y = 537;

            a.text = "";

            a.addEventListener(FocusHandlerEvent.FOCUS_IN, inputBoxGainFocus, false, 0, true);
            a.addEventListener(FocusHandlerEvent.FOCUS_OUT, inputBoxLoseFocus, false, 0, true);*/
        }

        // Instantly ask for the current state
        public function requestCurrentStateInsant() {
            // Check if we've recently gotten an update
            if(this.globals.Game.Time() - this.lastUpdate < 2) {
                return;
            }

            // Reset initial state received
            this.gottenInitialState = false;

            // Send our version, and request the current state
            var ver = Globals.instance.GameInterface.LoadKVFile("scripts/version.txt").version;
            gameAPI.SendServerCommand("afs_request_state \""+ver+"\"");

            // Update when we last requested an update
            this.lastUpdate = this.globals.Game.Time();
        }

        // Ask for the current state after a delay
        public function requestCurrentState() {
            // Request the current game state (after a delay)
            var timer:Timer = new Timer(1000, 1);
            timer.addEventListener(TimerEvent.TIMER, function(e:TimerEvent) {
                // Ask for the current state
                requestCurrentStateInsant();
            });
            timer.start();
        }

        public function inputBoxGainFocus() {
            if(!bGotInput) {
                bGotInput = true;
                Globals.instance.GameInterface.AddKeyInputConsumer();
            }
        }

        public function inputBoxLoseFocus() {
            if(bGotInput) {
                bGotInput = false;
                Globals.instance.GameInterface.RemoveKeyInputConsumer();
            }
        }

        public function cleanHud() {
            var key;

            // Remove all items from the hud
            for(key in stateCleanup) {
                removeChild(stateCleanup[key]);
            }

            for(key in stateCleanupSpecial) {
                removeChild(stateCleanupSpecial[key]);
            }

            // Create new store
            stateCleanup = new Array();
            stateCleanupSpecial = {};

            // Cleanup content panel
            if(contentPanelHolder != null) {
                // Remove everything from the content panel
                while (contentPanelHolder.source.numChildren > 0) {
                    contentPanelHolder.source.removeChildAt(0);
                }

                // Make it invisible
                contentPanelHolder.visible = false;

                // Remove the content panel
                //removeChild(contentPanelHolder)
                //contentPanelHolder = null;
            }
        }

        public function autoCleanup(mc) {
            // Add to the main area
            addChild(mc);

            // Set it for cleanup
            stateCleanup.push(mc);
        }

        public function autoCleanupSpecial(mc, name) {
            // Add to the main area
            addChild(mc);

            // Set it for cleanup
            stateCleanupSpecial[name] = mc;
        }

        public function getSpecial(name) {
            return stateCleanupSpecial[name];
        }

        public function removeSpecial(name) {
            var mc = getSpecial(name);
            if(mc && this.contains(mc)) {
                this.removeChild(mc);
                stateCleanupSpecial[name] = null;
            }
        }

        public function makeTextField(txtSize:Number):TextField {
            var txt:TextField = new TextField();
            var textFormat:TextFormat = new TextFormat();
            textFormat.size = txtSize;
            textFormat.align = TextFormatAlign.LEFT;
            txt.defaultTextFormat = textFormat;

            txt.text = "change this";
            txt.textColor = 0xFFFFFF;
            txt.selectable = false;

            return txt;
        }

        public function receiveInitialState(args:Object) {
            // If we already have the initial state, ignore
            if(this.gottenInitialState) return;
            this.gottenInitialState = true;

            // Process the state
            processState(args);
        }

        public function processState(args:Object) {
            // Cleanup anything from old states
            cleanHud();

            // Store the last state data
            this.lastStateData = args;

            // Parse data
            var data = decode(args.d);

            // Update timers if there are any
            if(data.timers) {
                this.updateTimers(data.timers);
            }

            // Update the scores
            this.updateScore({
                scoreDire: data.scoreDire,
                scoreRadiant: data.scoreRadiant
            });

            switch(args.nState) {
                case STATE_INIT:
                    // Nothing has even happened yet
                break;

                case STATE_PICKING:
                    this.ProcessPickingData(data);
                    this.BuildPickingScreen();
                    hideGame.visible = true;
                break;

                case STATE_VOTING:
                    this.BuildVoteScreen(data);
                    hideGame.visible = true;
                break;

                case STATE_PLAYING:
                    hideGame.visible = false;
                break;

                default:
                    trace("Dont know how to process: "+args.nState);
                break;
            }
        }

        public function ProcessPickingData(data) {
            var s:String;

            // Reset the picking data
            pickingData = {};
            pickingData.builds = data.b;
            pickingData.heroes = data.h;

            // Check if we can pick skills
            if(data.s) {
                // Create an array for skills
                pickingData.skills = [];

                // Build skill list
                for(var name in data.s) {
                    // Grab info on this skill
                    var info = data.s[name];

                    // Check if it's banned
                    var banned = false;
                    if(info.b) banned = true;

                    // Push the skill
                    pickingData.skills.push({
                        skillName: name,
                        skillSort: info.c,
                        skillHero: info.h,
                        banned: banned
                    })
                }

                // Sort it
                pickingData.skills.sort(function(a, b) {
                    // Grab translated heroes
                    var ha = Translate("#"+a.skillHero);
                    var hb = Translate("#"+b.skillHero);

                    // Sort by hero, then type, then skill name
                    if(ha < hb) {
                        return -1;
                    } else if(ha > hb) {
                        return 1;
                    } else {
                        // Grab ability types
                        var ta = a.skillSort;
                        var tb = b.skillSort;

                        if(ta < tb) {
                            return -1;
                        } else if(ta > tb) {
                            return 1;
                        } else {
                            // Grab translated skill names
                            var na = Translate("#DOTA_Tooltip_ability_"+a.skillName);
                            var nb = Translate("#DOTA_Tooltip_ability_"+b.skillName);

                            if(na < nb) {
                                return -1;
                            } else if(na > nb) {
                                return 1;
                            } else {
                                // Compare based on their raw skill name
                                if(a.skillName < b.skillName) {
                                    return -1;
                                } else if(a.skillName > b.skillName) {
                                    return 1;
                                } else {
                                    return 0;
                                }
                            }
                        }
                    }
                });
            }

            // Store hero builds
            this.updateBuildData(data.b);
        }

        public function updateBuildData(data) {
            var skill, i:Number, j:Number, skillName:String;

            // Clear out current builds
            pickingData.builds = data;

            // Find icons for local hero
            var localSkills = [];

            // Grab playerID to build skill list
            var playerID = globals.Players.GetLocalPlayer();

            if(playerID >= 0 && playerID <= 9) {
                // Update our local skill list
                localSkills = pickingData.builds[playerID].s;
            }

            // Update icons for your local hero
            var hero = getSpecial('localhero');
            if(hero) {
                hero.UpdateHero(pickingData.builds[playerID].h);
            }

            for(i=0; i<maxSkills; i++) {
                // Attempt to grab this skill
                skill = getSpecial('skill_'+i);
                if(skill) {
                    // Grab name of this skill
                    skillName = localSkills[i];
                    if(!skillName) skillName = 'doom_bringer_empty1';

                    // Found it, update it
                    skill.UpdateSkill(skillName);
                }
            }

            // The last set that is visible
            var lastVisible = 0;

            // Side icons
            for(i=0; i<10; i++) {
                var build = pickingData.builds[i];
                if(build) {
                    var shouldDisplay = (globals.Players.GetPlayerHeroEntityIndex(i) != -1);

                    if(shouldDisplay) lastVisible = i;

                    // Update Hero Image
                    skill = getSpecial('hero_'+i);
                    if(skill) {
                        skill.UpdateHero(build.h);
                        skill.visible = shouldDisplay;
                    }

                    // Update ready state
                    skill = getSpecial('ready_'+i);
                    if(skill) skill.visible = shouldDisplay && build.r;

                    // Update steam avatar
                    skill = getSpecial('avatar_'+i);
                    if(skill) skill.visible = shouldDisplay;

                    for(j=0; j<maxSkills; j++) {
                        skill = getSpecial('skill_'+i+'_'+j);
                        if(skill) {
                            // Grab name of this skill
                            skillName = build.s[j];
                            if(!skillName) skillName = 'doom_bringer_empty1';

                            // Found it, update it
                            skill.UpdateSkill(skillName);
                            skill.visible = shouldDisplay;
                        }
                    }
                }
            }
        }

        public function updateBuildDataHook(args:Object) {
            if(args.d) {
                this.updateBuildData(decode(args.d));
            }
        }

        public function updateSteamIDs(args:Object) {
            if(args.d) {
                var data = decode(args.d);

                for(var i=0; i<10; i++) {
                    var newID = data[i];
                    if(!newID) newID = 0;

                    if(this.steamIDs[i] != newID) {
                        // Attempt to update avatar images
                        var skill = getSpecial('avatar_'+i);
                        if(skill) {
                            Globals.instance.LoadImage('img://[M' + newID + ']', skill, false);
                        }

                        // Store new steamID
                        this.steamIDs[i] = newID;
                    }
                }
            }
        }

        public function updateScoreHook(args:Object) {
            if(args.d) {
                // Update the timers
                this.updateScore(decode(args.d));
            }
        }

        public function updateScore(scores:Object) {
            // Cleanup old scores
            removeSpecial("score_dire");
            removeSpecial("score_radiant");

            // Distance from the middle
            var distanceFromMiddle = 24;

            if(scores.scoreRadiant != null) {
                var scoreRadiant = makeTextField(18);
                scoreRadiant.text = scores.scoreRadiant;
                autoCleanupSpecial(scoreRadiant, "score_radiant");
                scoreRadiant.width = scoreRadiant.textWidth;
                scoreRadiant.x = maxStageWidth/2 - scoreRadiant.width - distanceFromMiddle;
                scoreRadiant.y = 32;
            }

            if(scores.scoreDire != null) {
                var scoreDire = makeTextField(18);
                scoreDire.text = scores.scoreDire;
                autoCleanupSpecial(scoreDire, "score_dire");
                scoreDire.width = scoreDire.textWidth;
                scoreDire.x = maxStageWidth/2 + distanceFromMiddle;
                scoreDire.y = 32;
            }
        }

        public function updateTimersHook(args:Object) {
            if(args.d) {
                // Update the timers
                this.updateTimers(decode(args.d));
            }
        }

        public function updateTimers(timers:Object) {
            var timer;

            // Remvoe all old timers
            for(var key in this.serverTimers) {
                timer = this.serverTimers[key];
                if(timer) {
                    // Check if there is still a timer running
                    if(timer.timer) timer.timer.stop();

                    // Remove from the screen
                    if(this.contains(timer)) removeChild(timer);
                }

                // Set it to null
                this.serverTimers[key] = null;
            }

            var xx = 0;
            var yy = 32;

            // Build new timers
            for(key in timers) {
                // Grab data
                var timerData = timers[key];
                var timeLeft = Math.floor(timerData.e - this.globals.Game.Time());

                // Create timer
                timer = new ServerTimer(timerData.t, timeLeft);
                addChild(timer);

                // Stop mouse interactions
                timer.mouseEnabled = false;
                timer.mouseChildren = false;

                // Move into position
                timer.x = xx;
                timer.y = yy;

                // Increase y
                yy += timer.height + 8;

                // Store timer
                this.serverTimers[key] = timer;
            }
        }

        public function updateVoteStatus(args:Object) {
            // Make sure we have the vote info
            if(voteHolder == null) return;

            // Grab the data
            var data = decode(args.d);

            for (var name:String in data) {
                var voteInfo = data[name];

                // Create vote panel
                var vote = voteHolder[name];

                // Check if we found it
                if(vote != null) {
                    // Update the count
                    vote.updateCount(voteInfo.count);
                } else {
                    trace("Failed to find "+name);
                }
            }
        }

        public function newPanel() : void {
            // Check if we already have a content panel
            if(contentPanelHolder != null) {
                // Remove everything from the content panel
                while (contentPanelHolder.source.numChildren > 0) {
                    contentPanelHolder.source.removeChildAt(0);
                }

                // Make it visible
                contentPanelHolder.visible = true;
            } else {
                // Create new content panel
                contentPanelHolder = new ScrollPane();
                addChild(contentPanelHolder)

                // Setup the panel where the icons will go
                contentPanel = new MovieClip();
                contentPanelHolder.source = contentPanel;
            }

            // Position and size the content panel
            contentPanelHolder.x = 224;
            contentPanelHolder.y = 64;
            contentPanelHolder.setSize(maxStageWidth-sideTotalWidth-sidePaddingX-contentPanelHolder.x-24, maxStageHeight - iconHeight - bottomMargin - 120);

        }

        public function addPanelChild(clip:MovieClip) {
            contentPanel.addChild(clip);
        }

        public function updatePanel() {
            contentPanelHolder.update();
        }

        public function getContentWidth() {
            return contentPanelHolder.width;
        }

        public function getContentHeight() {
            return contentPanelHolder.height;
        }

        public function skillIntoSlot(skillName, slotNumber) {
            this.gameAPI.SendServerCommand("afs_skill \""+skillName+"\" "+slotNumber);
        }

        public function selectHero(heroName) {
            this.gameAPI.SendServerCommand("afs_hero \""+heroName+"\"");
        }

        public function votePressed(e:Event) {
            var vote = e.currentTarget.parent;
            this.gameAPI.SendServerCommand("afs_vote \""+vote.optionName+"\"");
        }

        public function skillClicked(e:Event) {
            if(selectedSkill != null) {
                removeChild(selectedSkill);
            }

            var s = e.currentTarget;
            selectedSkill = new Skill(s.skillName, s.skillSort, s.skillHero);
            addChild(selectedSkill);
            selectedSkill.x = 480;
            selectedSkill.y = 554;
        }

        public function strRep(str, count) {
            var output = "";
            for(var i=0; i<count; i++) {
                output = output + str;
            }

            return output;
        }

        public function PrintTable(t, indent) {
            for(var key in t) {
                var v = t[key];

                if(typeof(v) == "object") {
                    trace(strRep("\t", indent)+key+":")
                    PrintTable(v, indent+1);

                    if(v.gameAPI) {
                        trace(strRep("\t", indent+1)+"gameAPI:")
                        PrintTable(v.gameAPI, indent+2);
                    }
                } else {
                    trace(strRep("\t", indent)+key.toString()+": "+v.toString());
                }
            }
        }

        public function onScreenSizeChanged() : void {
            // Align to top of screen
            x = 0;
            y = 0;

            // Lets assume the height never changes:
            maxStageWidth = stage.stageWidth / stage.stageHeight * 768;

            // Check if we have any state data
            if(this.lastStateData) {
                // Rebuild the hud
                this.processState(this.lastStateData);
            }
        }

        public function onResize(re:ResizeManager) : * {
            // Align to top of screen
            x = 0;
            y = 0;

            // Update the stage width
            maxStageWidth = re.ScreenWidth / re.ScreenHeight * 768;

            // Scale hud up
            this.scaleX = re.ScreenWidth/maxStageWidth;
            this.scaleY = re.ScreenHeight/maxStageHeight;

            // Check if we have any state data
            if(this.lastStateData) {
                // Rebuild the hud
                this.processState(this.lastStateData);
            }
        }

        // Displays the skill info thing about a given skill (requires rollOver event)
        public function onSkillRollOver(e:MouseEvent) {
            // Grab what we rolled over
            var s = e.target;

            // Workout where to put it
            var lp = s.localToGlobal(new Point(0, 0));

            // Display the info
            globals.Loader_heroselection.gameAPI.OnSkillRollOver(lp.x, lp.y, s.skillName);
        }

        // Hides the skill info thing (Requires rollOut event)
        public function onSkillRollOut(e:MouseEvent) {
            globals.Loader_heroselection.gameAPI.OnSkillRollOut();
        }

        public function changeToTabSkills() {
            // Change the tab
            currentPickerTab = TAB_SKILL_PICKER;

            // Clean the hud
            cleanHud();

            // Reload picking
            BuildPickingScreen()
        }

        public function changeToTabHero() {
            // Change the tab
            currentPickerTab = TAB_HERO_PICKER;

            // Clean the hud
            cleanHud();

            // Reload picking
            BuildPickingScreen()
        }

        public function BuildPickingScreen() {
            var skill:MovieClip, hero:MovieClip, btn, i:Number, j:Number, xpadding:Number, ypadding:Number, totalWidth:Number, skillName:String, heroName:String, sx:Number, sy:Number, xx:Number, yy:Number;

            // Create a new panel for the skills
            newPanel();

            // Position of the first button
            xx = contentPanelHolder.x;
            yy = 32;

            // Add tab changing buttons

            // Skill picker button
            if(pickingData.skills) {
                btn = new Button();
                autoCleanup(btn);
                btn.x = xx;
                btn.y = yy;
                btn.label = '#afs_tab_pick_skills';
                btn.addEventListener(MouseEvent.CLICK, changeToTabSkills, false, 0, true);

                // Move the position of the next button
                xx += btn.width + 8;

                // Change to this tab, if none is selected
                if(this.currentPickerTab == TAB_NONE) {
                    this.currentPickerTab = TAB_SKILL_PICKER;
                }
            } else {
                // Check if we are on an invalid tab
                if(this.currentPickerTab == TAB_SKILL_PICKER) {
                    // Check if the hero tab exists
                    if(pickingData.heroes) {
                        // Change to hero picker tab
                        this.currentPickerTab = TAB_HERO_PICKER;
                    } else {
                        // Display no tab
                        this.currentPickerTab = TAB_NONE;
                    }
                }
            }

            // Hero picker button
            if(pickingData.heroes) {
                btn = new Button();
                autoCleanup(btn);
                btn.x = xx;
                btn.y = yy;
                btn.label = '#afs_tab_pick_hero';
                btn.addEventListener(MouseEvent.CLICK, changeToTabHero, false, 0, true);

                // Change to this tab, if none is selected
                if(this.currentPickerTab == TAB_NONE) {
                    this.currentPickerTab = TAB_HERO_PICKER;
                }
            } else {
                // Check if we are on an invalid tab
                if(this.currentPickerTab == TAB_HERO_PICKER) {
                    // Check if the skills tab exists
                    if(pickingData.skills) {
                        // Change to skill picker tab
                        this.currentPickerTab = TAB_SKILL_PICKER;
                    } else {
                        // Display no tab
                        this.currentPickerTab = TAB_NONE;
                    }
                }
            }

            // Setting for skill picking panel
            var padding:Number = 4;
            var xo = 16;//(getContentWidth() - Math.floor(getContentWidth()/(iconWidth+padding))*iconWidth)/4;
            xx = xo;
            yy = 0;

            if(this.currentPickerTab == TAB_HERO_PICKER) {
                // Hero picking tab

                // Put hero icons in
                for(heroName in pickingData.heroes) {
                    // Create a new hero icon
                    hero = new HeroIcon(heroName)
                    addPanelChild(hero);
                    hero.x = xx;
                    hero.y = yy;

                    // Allow dragging from this
                    dragMakeValidFrom(hero);

                    // Grab the position of the next icon
                    xx = xx + heroIconWidth + padding;
                    if(xx+iconWidth > getContentWidth()) {
                        xx = xo;
                        yy = yy + heroIconHeight + padding;
                    }
                }
            }else if(this.currentPickerTab == TAB_SKILL_PICKER) {
                // Skill picking tab

                // Put all the icons in
                for each (var skillInfo in pickingData.skills) {
                    // Create a new skill icon
                    skill = new Skill(skillInfo.skillName, skillInfo.skillSort, skillInfo.skillHero);
                    addPanelChild(skill);
                    skill.x = xx;
                    skill.y = yy;

                    // Allow dragging from this
                    dragMakeValidFrom(skill);

                    //skill.addEventListener(MouseEvent.CLICK, this.skillClicked);
                    skill.addEventListener(MouseEvent.ROLL_OVER, this.onSkillRollOver, false, 0, true);
                    skill.addEventListener(MouseEvent.ROLL_OUT, this.onSkillRollOut, false, 0, true);

                    xx = xx + iconWidth + padding;
                    if(xx+iconWidth > getContentWidth()) {
                        xx = xo;
                        yy = yy + iconHeight + padding;
                    }
                }
            }

            // Update the scrollbar
            updatePanel();

            // Find icons for local hero
            var localSkills = [];

            // Grab playerID to build skill list
            var playerID = globals.Players.GetLocalPlayer();

            if(playerID >= 0 && playerID <= 9) {
                // Update our local skill list
                localSkills = pickingData.builds[playerID].s;
            }

            // Put icons for your local hero

            xpadding = 16;
            totalWidth = (iconWidth+xpadding) * maxSkills - xpadding;

            xx = (maxStageWidth - totalWidth) / 2;
            yy = maxStageHeight - iconHeight - bottomMargin - 32;

            hero = new HeroIcon(pickingData.builds[playerID].h);
            autoCleanupSpecial(hero, 'localhero');
            hero.x = xx;
            hero.y = yy + iconHeightX - heroIconHeightX;
            dragMakeValidTarget(hero);

            // Move into new position
            xx += heroIconWidth + xpadding;

            for(i=0; i<maxSkills; i++) {
                // Grab name of this skill
                skillName = localSkills[i];
                if(!skillName) skillName = 'doom_bringer_empty1';

                // Create a skill
                skill = new Skill(skillName, '', '');
                autoCleanupSpecial(skill, 'skill_'+i);
                skill.x = xx;
                skill.y = yy;

                // Store slot number as name
                skill.name = String(i+1);

                // Allow dragging to this slot
                dragMakeValidTarget(skill)

                // Hook the skill
                skill.addEventListener(MouseEvent.ROLL_OVER, this.onSkillRollOver, false, 0, true);
                skill.addEventListener(MouseEvent.ROLL_OUT, this.onSkillRollOut, false, 0, true);

                // Move it into position
                xx += iconWidth + xpadding;
            }

            // Side icons (Other people's builds)

            // Workout where to place them
            sx = maxStageWidth - sideTotalWidth;
            sy = 64;
            xx = sx;
            yy = sy;

            // Grab total players
            var totalPlayers = globals.Players.GetMaxPlayers();

            var lastVisible = 0;

            // Loop over all 10 builds
            for(i=0; i<10; i++) {
                // Grab and validate the build
                var build = pickingData.builds[i];
                if(build) {
                    // Check if we should show these stats
                    var shouldDisplay = (globals.Players.GetPlayerHeroEntityIndex(i) != -1);

                    // If so, store this as the last visible
                    if(shouldDisplay) lastVisible = i;

                    // Ready state
                    skill = new MovieClip();
                    autoCleanupSpecial(skill, 'ready_'+i);
                    skill.x = xx;
                    skill.y = yy;
                    skill.visible = shouldDisplay && build.r;
                    Globals.instance.LoadImage('images/hud/tick.png', skill, false);
                    skill.scaleX = 0.5;
                    skill.scaleY = 0.5;

                    xx += iconMiniSize + sidePaddingX;

                    // User's Steam Picture
                    skill = new MovieClip();
                    autoCleanupSpecial(skill, 'avatar_'+i);
                    skill.x = xx;
                    skill.y = yy;
                    skill.visible = shouldDisplay;
                    Globals.instance.LoadImage('img://[M' + this.steamIDs[i] + ']', skill, false);
                    skill.scaleX = 16/avatarSize;
                    skill.scaleY = 16/avatarSize;

                    xx += iconMiniSize + sidePaddingX;

                    // Create hero image thingo
                    var heroIcon = new HeroDisplayMini(build.h);
                    autoCleanupSpecial(heroIcon, 'hero_'+i);
                    heroIcon.x = xx;
                    heroIcon.y = yy;
                    heroIcon.visible = shouldDisplay;
                    dragMakeValidFrom(heroIcon);

                    xx += 128/4.5 + sidePaddingX;

                    // Loop over all the skills in the build
                    for(j=0; j<maxSkills; j++) {
                        // Grab name of this skill
                        skillName = build.s[j];
                        if(!skillName) skillName = 'doom_bringer_empty1';

                        // Create a mini skill icon for it
                        skill = new SkillMini(skillName);
                        autoCleanupSpecial(skill, 'skill_'+i+'_'+j);
                        skill.x = xx;
                        skill.y = yy;
                        skill.visible = shouldDisplay;

                        // Allow dragging from this
                        dragMakeValidFrom(skill);

                        // Make it display info
                        skill.addEventListener(MouseEvent.ROLL_OVER, this.onSkillRollOver, false, 0, true);
                        skill.addEventListener(MouseEvent.ROLL_OUT, this.onSkillRollOut, false, 0, true);

                        xx += iconMiniSize + sidePaddingX;
                    }
                }

                xx = sx;
                yy += iconMiniSize + sidePaddingY;
            }

            // Add ready button
            var readyButton = new Button();
            readyButton.x = sx + (sideTotalWidth-readyButton.width)/2;
            readyButton.y = sy + getContentHeight();
            readyButton.label = "#afs_toggle_ready";
            readyButton.addEventListener(MouseEvent.CLICK, this.readyPressed, false, 0, true);
            autoCleanup(readyButton);
        }

        public function readyPressed() {
            gameAPI.SendServerCommand("afs_ready_pressed");
        }

        public function BuildVoteScreen(data) {
            // Create a new panel for the skills
            newPanel();

            // Setting for skill picking panel
            var padding:Number = 8;
            var xo = padding;
            var xx:Number = xo;
            var yy:Number = padding;

            // This will store all the vote panels
            voteHolder = {};

            // Fill it with vote options
            for(var name:String in data.options) {
                var voteInfo = data.options[name];

                // Create vote panel
                var vote = new VoteButton(name, voteInfo.des, voteInfo.count);
                addPanelChild(vote);
                vote.x = xx;
                vote.y = yy;

                // Listen to button press
                vote.Button.addEventListener(MouseEvent.CLICK, this.votePressed, false, 0, true);

                // Store this panel
                voteHolder[name] = vote;

                // Move the next panel down
                yy = yy + voteHeight + padding;
            }

            // Update the scrollbar
            updatePanel();
        }

        // Makes this movieclip draggable
        public function dragMakeValidFrom(mc) {
            mc.addEventListener(MouseEvent.MOUSE_DOWN, dragMousePressed, false, 0, true);
            mc.addEventListener(MouseEvent.MOUSE_UP, dragMouseReleased, false, 0, true);
            mc.addEventListener(MouseEvent.ROLL_OUT, dragFromRollOut, false, 0, true);
        }
        // Makes this movieclip into a valid target
        public function dragMakeValidTarget(mc) {
            mc.addEventListener(MouseEvent.ROLL_OVER, dragTargetRollOver, false, 0, true);
            mc.addEventListener(MouseEvent.ROLL_OUT, dragTargetRollOut, false, 0, true);
        }
        public function dragListener(e:MouseEvent) {
            dragClip.x = mouseX;
            dragClip.y = mouseY;
        }
        public function dragTargetRollOver(e:MouseEvent) {
            // Check if we can even drag here
            if(e.target.dragSort == dragSort) {
                dragTarget = e.target;
            }
        }
        public function dragMouseUp(e:MouseEvent) {
            dragClickedClip = null;
            if(dragClip) {
                if(dragTarget) {
                    if(dragSort == DRAG_SORT_SKILL) {
                        // Put a skill into a slot
                        skillIntoSlot(dragClip.name, dragTarget.name);
                    } else if(dragSort == DRAG_SORT_HERO) {
                        // Select a hero
                        selectHero(dragClip.name);
                    }
                }

                // Remove drag object
                removeChild(dragClip);
                dragClip = null;

                // Remove move event
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, dragListener);
            }

            stage.removeEventListener(MouseEvent.MOUSE_UP, dragMouseUp)
        }
        public function dragMousePressed(e:MouseEvent) {
            dragClickedClip = e.currentTarget;
            dragTarget = null;
        }
        public function dragMouseReleased(e:MouseEvent) {
            dragClickedClip = null;
        }
        public function dragFromRollOut(e:MouseEvent) {
            // Check if this is the clip we tried to drag
            if(dragClickedClip == e.target) {
                // Check if there is already a drag clip
                if(dragClip && this.contains(dragClip)) {
                    // Remove drag object
                    removeChild(dragClip);
                    dragClip = null;
                }

                // Store new drag sort
                dragSort = dragClickedClip.dragSort

                // Make a new dragclip
                dragClip = new MovieClip();
                dragClip.mouseEnabled = false;
                addChild(dragClip);

                // Make it look nice / give it a name
                if(dragSort == DRAG_SORT_SKILL) {
                    // Skill icon
                    dragClip.name = dragClickedClip.skillName;
                    Globals.instance.LoadAbilityImage(dragClickedClip.skillName, dragClip);
                    dragClip.scaleX = 0.5;
                    dragClip.scaleY = 0.5;
                } else if (dragSort == DRAG_SORT_HERO) {
                    // Hero icon
                    dragClip.name = dragClickedClip.heroName;
                    Globals.instance.LoadHeroImage(dragClickedClip.heroName.replace('npc_dota_hero_', ''), dragClip);
                    dragClip.scaleX = 0.5;
                    dragClip.scaleY = 0.5;
                }

                // Add listeners
                stage.addEventListener(MouseEvent.MOUSE_MOVE, dragListener, false, 0, true);
                stage.addEventListener(MouseEvent.MOUSE_UP, dragMouseUp, false, 0, true);

                // Stop it from procing again
                dragClickedClip = null;
            }
        }
        public function dragTargetRollOut(e:MouseEvent) {
            // Validate target
            if(e.target == dragTarget) {
                // Remove drag target
                dragTarget = null;
            }
        }

        // JSON decoder
        public static function decode( s:String, strict:Boolean = true ):* {
            return new JSONDecoder( s, strict ).getValue();
        }

        // JSON encoder
        public static function encode( o:Object ):String {
            return new JSONEncoder( o ).getString();
        }
    }
}
