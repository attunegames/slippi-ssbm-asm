#To be inserted at 801a45b8
.include "../../Common/Common.s"
.include "Online/Online.s"
#.include "../Globals.s"
.include "Header.s"

.set  ExitSceneID,40

# Original codeline
  addi	r29, r3, 4

#region Init New Scenes
.set  REG_MinorSceneStruct,31

#Init and backup
  backup

################################################################################
# Set text entry keyboard to qwerty
################################################################################
/*
  load r3, 0x803EDC1C # destination
  bl DATA_BLRL
  mflr r4
  addi r4, r4, DOFST_QWERTY_LAYOUT
  li r5, QWERTY_LAYOUT_LEN
  branchl r12, memcpy
*/

################################################################################
# Initialize hashtag letter in text entry
################################################################################
  load r4, 0x803EDC1C # Start of keyboard (top-right, goes down first)
  bl DATA_BLRL
  mflr r3
  addi r3, r3, DOFST_HASHTAG_LETTER
  stw r3, 0x8(r4) # Third letter down from top-right

################################################################################
# Initialize some variables
################################################################################
  li r3, 0
  stb r3, OFST_R13_NAME_ENTRY_MODE(r13)
  stb r3, OFST_R13_ISPAUSE(r13)
  stb r3, OFST_R13_USE_PREMADE_TEXT(r13)
  stb r3, isWidescreen(r13)

################################################################################
# Set up Slippi major scene
################################################################################
#Init Slippi major struct
  li  r3,SlippiMajorID
  bl  Slippi_MinorSceneStruct
  mflr  r4
  bl  InitializeMajorSceneStruct

  b Injection_Exit

#region PointerConvert
PointerConvert:
  lwz r4,0x0(r3)          #Load bl instruction
  rlwinm r5,r4,8,25,29    #extract opcode bits
  cmpwi r5,0x48           #if not a bl instruction, exit
  bne PointerConvert_Exit
  rlwinm  r4,r4,0,6,29  #extract offset bits
  extsh r4,r4
  add r4,r4,r3
  stw r4,0x0(r3)
PointerConvert_Exit:
  blr
#endregion
#region InitializeMajorSceneStruct
InitializeMajorSceneStruct:
.set  REG_MajorScene,31
.set  REG_MinorStruct,30

#Init
  backup
  mr  REG_MajorScene,r3
  mr  REG_MinorStruct,r4

# Set up Load and Unload functions
/*
Major Scene Table:
    -Starts at 803daca4
    -Stride is 0x14
    -Structure is:
        -0x0 = Preload Bool. (0x0 = No Preload, 0x1 = Preload)
        -0x1 = Major Scene ID
        -0x2 = Unk
        -0x3 = Unk
        -0x4 = Pointer to MajorLoad Function (is run upon entering the major)
        -0x8 = Pointer to MajorUnload Function (is run upon leaving the major)
        -0xC = Pointer to MajorOnBoot Function (is run on boot to init global stuff)
        -0x10 = Pointer to Minor Scenes Tables
*/
  load r4, 0x803dad30 # Start of 0x8 major scene table entry
  bl MajorSceneLoad
  mflr r3
  stw r3, 0x4(r4)
  bl MajorSceneUnload
  mflr r3
  stw r3, 0x8(r4)
  li  r3,1
  stb r3,0x0(r4)    # preload bool


#Get major scene struct
  #branchl r12,0x801a50ac
  load r3,0x803daca4
GetMajorStruct_Loop:
  lbz	r4, 0x0001 (r3)
  cmpw r4,REG_MajorScene
  beq GetMajorStruct_Exit
  addi  r3,r3,20
  b GetMajorStruct_Loop
GetMajorStruct_Exit:

InitMinorSceneStruct:
.set  REG_MinorStructParse,20
  stw REG_MinorStruct,0x10(r3)
  mr  REG_MinorStructParse,REG_MinorStruct
InitMinorSceneStruct_Loop:
#Check if valid entry
  lbz r3,0x0(REG_MinorStructParse)
  extsb r3,r3
  cmpwi r3,-1
  beq InitMinorSceneStruct_Exit
#Convert Pointers
  addi  r3,REG_MinorStructParse,0x4
  bl  PointerConvert
  addi  r3,REG_MinorStructParse,0x8
  bl  PointerConvert
  addi  r3,REG_MinorStructParse,0x10
  bl  PointerConvert
  addi  r3,REG_MinorStructParse,0x14
  bl  PointerConvert  
  addi  REG_MinorStructParse,REG_MinorStructParse,0x18
  b InitMinorSceneStruct_Loop
InitMinorSceneStruct_Exit:

  restore
  blr
#endregion
#endregion

MajorSceneLoad:
blrl
backup

################################################################################
# Rooms open on their own screen
################################################################################
# The menu cannot choose where a major lands. Event_StoreSceneNumber sets the
# major and flags the minor exit, and then the major TRANSITION picks the first
# minor itself - so a pending minor written in the menu is overwritten before
# anything here runs. Writing minor 6 from FN_OnlineSubmenuThink_GO_TO_ROOM
# alone puts you on the character select every time.
#
# This is the first code that runs inside the new major, which makes it the
# earliest place the choice survives. Both bytes: +0x5 is the pending minor and
# +0x3 is the current one.
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
bne ROOMS_MAJOR_NOT_ROOMS
load r4, 0x80479d30
li r3, 6            # minor 6 = the room, not 0 (the character select)
stb r3, 0x5(r4)
stb r3, 0x3(r4)
logf LOG_LEVEL_NOTICE, "[Rooms] online major load - picking the room"
ROOMS_MAJOR_NOT_ROOMS:

# Set the proper 1p port for CSS
load r4, 0x8045abf0
lbz r3, -0x5108(r13) # player index
stb r3, 0x6(r4)

# Set the callback to determine winner at the end of the match
bl GamePrepData_BLRL
mflr r4
bl SinglesDetermineWinner_BLRL
mflr r3
stw r3, GPDO_FN_COMPUTE_RANKED_WINNER(r4)

################################################################################
# Set up Zelda to select Sheik as default
################################################################################
.set REG_IconData, 20
.set REG_IconNum, 21
.set REG_Count, 22

# get CSS icon data
  branchl r12,FN_GetCSSIconData
  mr REG_IconData,r3
# get icon num
  branchl r12,FN_GetCSSIconNum
  mr REG_IconNum,r3
# init search
  li REG_Count, 0
  b ZeldaSearch_Check
ZeldaSearch_Loop:
# check for zelda
  lbz	r3, 0x00DD (REG_IconData) # char id
  cmpwi r3,0x12
  bne ZeldaSearch_Inc
# store sheik's ID
  li r3,0x13
  stb	r3, 0x00DD (REG_IconData) # char id
  b ZeldaSearch_End
ZeldaSearch_Inc:
  addi REG_Count,REG_Count,1
  addi REG_IconData,REG_IconData,28
ZeldaSearch_Check:
  cmpw REG_Count,REG_IconNum
  blt ZeldaSearch_Loop
ZeldaSearch_End:


restore
blr

MajorSceneUnload:
blrl
backup

################################################################################
# Set up Zelda to select Zelda as default
################################################################################
li r3, 0x12
load r4, 0x803f0cc8
stb r3, 0x1(r4)

restore
blr

#region MinorSceneStruct
Slippi_MinorSceneStruct:
blrl
#CSS
.byte 0                     #Minor Scene ID
.byte 3                    #Amount of persistent heaps
.align 2
bl CSSScenePrep             #ScenePrep (event css prep), prev 0x801baa60
bl CSSSceneDecide        #SceneDecide, previously 0x801baad0
.byte 8                     #Common Minor ID (CSS)
.align 2
.long 0x80497758           #Minor Data 1
.long 0x80497758           #Minor Data 2
#SSS
.byte 1                     #Minor Scene ID
.byte 3                    #Amount of persistent heaps
.align 2
bl  SSSScenePrep            #ScenePrep, prev 0x801b1514
bl  SSSSceneDecide          #SceneDecide, prev 0x801b154c
.byte 9                     #Common Minor ID (SSS)
.align 2
.long 0x80480668            #Minor Data 1
.long 0x80480668            #Minor Data 2
#VS
.byte 2                     #Minor Scene ID
.byte 3                    #Amount of persistent heaps
.align 2
.long 0x801b1588            #ScenePrep
bl  VSSceneDecide          #SceneDecide, previously 0x801b15c8
.byte 2                    #Common Minor ID (VS Mode)
.align 2
.long 0x80480530            #Minor Data 1
.long 0x80479d98            #Minor Data 2
#Results
.byte 3                     #Minor Scene ID
.byte 3                    #Amount of persistent heaps
.align 2
.long 0x801b16a8            #ScenePrep, use default
.long 0x801b16c8          #SceneDecide, use default. Luckily goes back to scene 1 (CSS) which is what we want
.byte 5                    #Common Minor ID (Results)
.align 2
.long 0x8047c020            #Minor Data 1
.long 0x00000000            #Minor Data 2
#Splash
.byte 4                     #Minor Scene ID
.byte 3                    #Amount of persistent heaps
.align 2
bl SplashScenePrep          #ScenePrep, previously 0x801b3500
bl SplashSceneDecide
.byte 0x20                  #Common Minor ID (Classic Mode Splash)
.align 2
.long 0x80490880            #Minor Data 1
.long 0x804d68d0            #Minor Data 2
#GameSetup
.byte 5                     #Minor Scene ID
.byte 3                    #Amount of persistent heaps
.align 2
bl GamePrepScenePrep      #ScenePrep
bl GamePrepSceneDecide    #SceneDecide
.byte 80                  #Common Minor ID (Game Preparation)
.align 2
bl GamePrepData           #Minor Data 1
bl GamePrepData           #Minor Data 2
#Room
# The room is a minor of THIS major, so none of Slippi's screens move: the
# character select keeps SlippiCSS.dat and only appears once two people are
# matched.
#
# Minor Data 1 and 2 are the SPLASH's, deliberately. 0x80490880 is the struct
# SceneLoad_ClassicModeSplash reads - two characters at +0x10 and +0x11, their
# costumes, and the stage - and the room calls that builder itself to put two
# characters across the top of the screen. Pointing somewhere else would mean
# the builder reading a struct nobody fills.
.byte 6                     #Minor Scene ID
.byte 3                     #Amount of persistent heaps
.align 2
bl RoomScenePrep            #ScenePrep
bl RoomSceneDecide          #SceneDecide
.byte 0x51                  #Common Minor ID (Room)
.align 2
.long 0x80490880            #Minor Data 1
.long 0x804d68d0            #Minor Data 2
#Practice: training in-game
# Waiting in a queue is exactly when somebody wants to be in training, so
# training is a minor of THIS major rather than a major of its own. Melee's
# training-in-game scene is common minor 0x04; MxScn.dat carries a COPY of it
# as 0x52, so real training mode keeps its own functions untouched and only the
# room's version comes through here.
.byte 7                     #Minor Scene ID
.byte 3                     #Amount of persistent heaps
.align 2
bl RoomTrainScenePrep       #ScenePrep
bl RoomTrainSceneDecide     #SceneDecide
.byte 0x52                  #Common Minor ID (training, no module)
.align 2
# Training's OWN minor data, read out of major 0x1c minor 2 - the descriptor
# Melee uses to reach this same scene. An in-game scene loads the match its
# minor data describes, so borrowing VS mode's here meant waiting on a match
# that was never going to arrive.
.long 0x8048e4c0            #Minor Data 1
.long 0x8048e5f8            #Minor Data 2
#Practice: training character select
.byte 8                     #Minor Scene ID
.byte 3                     #Amount of persistent heaps
.align 2
bl RoomTrainCSSPrep         #ScenePrep
bl RoomTrainCSSDecide       #SceneDecide
# 0x53, not 0x08: the same screen, but 0x08 is where Slippi attaches
# SlippiCSS.dat, and that module has no business running over a training
# session - it expects an online match and reads a float as if it were a
# pointer when there is none. MxScn.dat carries 0x53 as a copy with no module.
.byte 0x53                  #Common Minor ID (character select, no module)
.align 2
.long 0x8048e230            #Minor Data 1
.long 0x8048e230            #Minor Data 2
#Practice: training stage select
.byte 9                     #Minor Scene ID
.byte 3                     #Amount of persistent heaps
.align 2
.long ScenePrep_TrainingMode_SSS
bl RoomTrainSSSDecide       #SceneDecide
.byte 0x09                  #Common Minor ID (stage select)
.align 2
.long 0x8048e378            #Minor Data 1
.long 0x8048e378            #Minor Data 2
#Catch-all
# ⚠️ Melee looks a minor up by id, and when it runs off the end of the table it
# does not stop - it carries on with a null descriptor and calls whatever
# address 8 happens to contain. That is the "Unknown instruction at PC =
# 010000fc" crash, and without this it is one bad scene request away at all
# times.
#
# The lookup walks upwards until something matches, so a high id catches
# everything above us, and it is the room: whatever asked to go somewhere that
# does not exist here ends up back where it started, which is the worst that
# should ever happen.
.byte 0xFE                  #Minor Scene ID
.byte 3                     #Amount of persistent heaps
.align 2
bl RoomScenePrep            #ScenePrep
bl RoomSceneDecide          #SceneDecide
.byte 0x51                  #Common Minor ID (Room)
.align 2
.long 0x80490880            #Minor Data 1
.long 0x804d68d0            #Minor Data 2
#End
.byte -1
.align 2

DATA_BLRL:
blrl
# Hashtag Letter
.set DOFST_HASHTAG_LETTER, 0
.long 0x81940000
/*
.set DOFST_QWERTY_LAYOUT, DOFST_HASHTAG_LETTER + 4
.set QWERTY_LAYOUT_LEN, 50 * 4
.long 0x804D4DD4
.long 0x804D4CAC
.long 0x804D4CAC
.long 0x804D4D98
.long 0x804D4D9C
.long 0x804D4DE8
.long 0x804D4E24
.long 0x804D4CAC
.long 0x804D4DA8
.long 0x804D4DAC
.long 0x804D4DA0
.long 0x804D4E38
.long 0x804D4CAC
.long 0x804D4DB8
.long 0x804D4DBC
.long 0x804D4E3C
.long 0x804D4D90
.long 0x804D4E10
.long 0x804D4DC8
.long 0x804D4DCC
.long 0x804D4DEC
.long 0x804D4DB0
.long 0x804D4DFC
.long 0x804D4DDC
.long 0x804D4DE0
.long 0x804D4D94
.long 0x804D4DC0
.long 0x804D4E20
.long 0x804D4DF0
.long 0x804D4DF4
.long 0x804D4DB4
.long 0x804D4DD0
.long 0x804D4E28
.long 0x804D4E04
.long 0x804D4E08
.long 0x804D4DE4
.long 0x804D4DF8
.long 0x804D4E0C
.long 0x804D4E18
.long 0x804D4E1C
.long 0x804D4E14
.long 0x804D4DA4
.long 0x804D4E00
.long 0x804D4E2C
.long 0x804D4E30
.long 0x804D4DC4
.long 0x804D4E34
.long 0x804D4DD8
.long 0x804D4E40
.long 0x804D4E44
*/
#endregion

GamePrepData_BLRL:
blrl
GamePrepData:
createGamePrepStaticBlock

#region CSSScenePrep
CSSScenePrep:
backup

#Restore saved fighter choice
lwz	r4, -0x77C0 (r13)
addi	r31, r4, 1328
branchl r12,0x801A427C
lbz	r5, 0x0002 (r31)
li	r4, 14
lbz	r7, 0x0003 (r31)
li	r6, 0
lbz	r8, 0x0004 (r31)
lbz	r10, 0x0006 (r31)
li	r9, 0
branchl r12,0x801B06B0

#Clear preload cache
branchl r12,0x800174bc

restore
blr
#endregion
#region CSSSceneDecide
CSSSceneDecide:
.set REG_MSRB_ADDR, 31
.set REG_MINORSCENE, 30
.set REG_EVENTCSS_DATA, 29
.set REG_VS_SSS_DATA, 28
.set REG_GAME_PREP_DATA, 27

backup
mr  REG_MINORSCENE,r3

# Run event mode CSS SceneDecide to save HMN character choice
branchl r12,0x801baad0

# Run generic CSS Scene Decide Copy ? to static match data
#branchl r12,0x801b14dc

# Check how CSS was exited
lwz r4,0x14(REG_MINORSCENE)
lbz r4,0x3(r4)
cmpwi r4,2
bne CSSSceneDecide_Advance
# Go back to Main Menu
#li  r3,1
#branchl r12,0x801a42f8
b CSSSceneDecide_Exit

CSSSceneDecide_Advance:
# Check for direct mode
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_RANKED
beq CSSSceneDecide_Adv_IsRanked
cmpwi r3, ONLINE_MODE_ROOMS
beq CSSSceneDecide_Adv_IsRoom
cmpwi r3, ONLINE_MODE_UNRANKED
beq CSSSceneDecide_Adv_IsUnranked
cmpwi r3, ONLINE_MODE_PARTY
beq CSSSceneDecide_Adv_IsUnranked
cmpwi r3, ONLINE_MODE_DIRECT
beq CSSSceneDecide_Adv_IsDirect
cmpwi r3, ONLINE_MODE_TEAMS
beq CSSSceneDecide_Adv_IsDirect

################################################################################
# Unranked Mode Logic
################################################################################
################################################################################
# Rooms: this screen is never on the way to a match
################################################################################
# Two people who have been paired go room -> draft -> game and never see it.
# Anybody who ends up here has finished a game, and belongs back in the room.
#
# ⚠️ Sharing the unranked answer - "load the splash and start playing" - is what
# overrules the room. The input handler on this screen asks for the room and
# ends the minor, then this runs and writes the splash over the top of the
# request. Melee starts a match, it ends at once because there is nothing to
# connect to, and it comes straight back here.
#
# No SplashSceneInit, deliberately: nothing is starting.
CSSSceneDecide_Adv_IsRoom:
load r4, 0x80479d30
li r3, MINOR_ROOM + 1
stb r3, 0x5(r4)
b CSSSceneDecide_Exit

CSSSceneDecide_Adv_IsUnranked:
b CSSSceneDecide_LoadSplash

################################################################################
# Ranked Mode Logic
################################################################################
CSSSceneDecide_Adv_IsRanked:
# Initialize ranked mode data
bl GamePrepData_BLRL
mflr REG_GAME_PREP_DATA

mr r3, REG_GAME_PREP_DATA
li r4, GPDO_SIZE
branchl r12, Zero_AreaLength

# Set the callback to determine winner at the end of the match,
# we just zero'd it so we have to set it again
bl SinglesDetermineWinner_BLRL
mflr r3
stw r3, GPDO_FN_COMPUTE_RANKED_WINNER(REG_GAME_PREP_DATA)

li r3, 3
stb r3, GPDO_MAX_GAMES(REG_GAME_PREP_DATA)
li r3, 1
sth r3, GPDO_CUR_GAME(REG_GAME_PREP_DATA)
li r3, 0
stb r3, GPDO_TIEBREAK_GAME_NUM(REG_GAME_PREP_DATA)
stb r3, GPDO_COLOR_BAN_ACTIVE(REG_GAME_PREP_DATA)

# Set next scene as game prep
load r4, 0x80479d30
li r3, 0x06
stb r3, 0x5(r4)
b CSSSceneDecide_Exit

################################################################################
# Direct Mode Logic
################################################################################
CSSSceneDecide_Adv_IsDirect:
# First match is random, advance to splash screen
lbz r3, OFST_R13_ISWINNER (r13)
extsb r3,r3
cmpwi r3,ISWINNER_NULL
beq CSSSceneDecide_LoadSplash

# Winner of last match does not decide stage, advance to splash screen
cmpwi r3,ISWINNER_WON
beq CSSSceneDecide_LoadSplash

# Loser of last match decides the stage, advance to SSS
cmpwi r3, ISWINNER_LOST
bne 0x0  # unhandled, stall
lbz r3, OFST_R13_CHOSESTAGE (r13)   # If the loser already decided the stage, advance to splash screen
cmpwi r3,0
beq CSSSceneDecide_LoadSSS
b CSSSceneDecide_LoadSplash

################################################################################
# Load Splash Screen
################################################################################
CSSSceneDecide_LoadSplash:
bl  SplashSceneInit

# Set next scene as Splash
load r4, 0x80479d30
li r3, 0x05
stb r3, 0x5(r4)
b CSSSceneDecide_Exit

################################################################################
# Load SSS
################################################################################
CSSSceneDecide_LoadSSS:
# Set next scene as SSS
load r4, 0x80479d30
li r3, 2
stb r3, 0x5(r4)
b CSSSceneDecide_Exit

CSSSceneDecide_Exit:
restore
blr
#endregion

#region SSSScenePrep
SSSScenePrep:
backup

# Call original function
branchl r12,0x801b1514

restore
blr
#endregion
#region SSSSceneDecide
SSSSceneDecide:
.set REG_MINORSCENE, 31
.set REG_MSRB_ADDR, 30

backup
mr  REG_MINORSCENE,r3

# Check how SSS was exited
lwz r4,0x14(REG_MINORSCENE)
lbz r4,0x4(r4)
cmpwi r4,0
bne SSSSceneDecide_Advance
SSSSceneDecide_Back:
# Go back to CSS
li  r3,0
branchl r12,0x801a42a0
b SSSSceneDecide_Exit

SSSSceneDecide_Advance:
# Set stage as selected
li  r3,1
stb r3,OFST_R13_CHOSESTAGE (r13)

# Get MSRB
li r3, 0
branchl r12, FN_LoadMatchState
mr  REG_MSRB_ADDR,r3

# Check to see if both players are ready and start match if they are
CHECK_SHOULD_START_MATCH:
lbz r3, MSRB_IS_LOCAL_PLAYER_READY(REG_MSRB_ADDR)
lbz r4, MSRB_IS_REMOTE_PLAYER_READY(REG_MSRB_ADDR)
cmpw  r3,r4
bne SSSSceneDecide_Advance_NotReady # If both players are not ready, go to CSS

SSSSceneDecide_Advance_IsReady:
# Both players are locked in, jump straight to splash screen
bl  SplashSceneInit         #init splash screen
# Set next scene as Splash
load r4, 0x80479d30
li r3, 0x05
stb r3, 0x5(r4)
b SSSSceneDecide_Exit

SSSSceneDecide_Advance_NotReady:
# Go back to CSS
li  r3,0
branchl r12,0x801a42a0
b SSSSceneDecide_Exit

SSSSceneDecide_Exit:
restore
blr
#endregion

FN_ReportSetCompletion:
backup
mr r31, r3

li r3, 2
branchl r12, HSD_MemAlloc

# Write tx data
li r4, CONST_SlippiCmdReportSetCompletion
stb r4, 0(r3)
stb r31, 1(r3)

# Transfer completion
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

restore
blr

#region VSSceneDecide
VSSceneDecide:
.set REG_MSRB_ADDR, 31
.set REG_TXB_ADDR, 30
.set REG_SHOULD_PICK_STAGE, 29
.set REG_WINNER_IDX, 28
.set REG_GPD, 27
.set REG_NEXT_SCENE, 26

backup

# Run original scene decide
branchl r12,0x801b15c8

# Get match state info
li r3, 0
branchl r12, FN_LoadMatchState
mr REG_MSRB_ADDR, r3

li REG_NEXT_SCENE, 1 # Default to going back to CSS

lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_RANKED
beq VSSceneDecide_Ranked
cmpwi r3, ONLINE_MODE_PARTY
beq VSSceneDecide_Party
cmpwi r3, ONLINE_MODE_ROOMS
beq VSSceneDecide_Rooms
b VSSceneDecide_GoToNextScene

# In Rooms a finished game goes to the room, and nowhere else.
#
# It gets there either way, but by way of the character select: the default is
# scene 1, that screen loads, and its own Decide sends it on to the room. The
# round trip takes a couple of hundred milliseconds and you can SEE it - the
# character select flashes up between every game. Naming the room here skips a
# screen with nothing to do.
VSSceneDecide_Rooms:
li REG_NEXT_SCENE, MINOR_ROOM + 1
b VSSceneDecide_GoToNextScene

VSSceneDecide_Party:
li REG_NEXT_SCENE, 4 # Go to results screen for party mode
b VSSceneDecide_DisconnectAndNextScene # Always disconnect after party mode

###########################################################################
# VSSceneDecide: Handle Ranked Mode
###########################################################################
VSSceneDecide_Ranked:
# If connection is not active, just go back to CSS
lbz r3, MSRB_CONNECTION_STATE(REG_MSRB_ADDR)
cmpwi r3, MM_STATE_IDLE
beq VSSceneDecide_Disconnected

# I think I can access ODB values here since we are still in the VS scene
# If last match ended in a disconnect, return to CSS
lwz r4, OFST_R13_ODB_ADDR(r13) # ODB address
lbz r3, ODB_IS_DISCONNECT_STATE_DISPLAYED(r4)
cmpwi r3, 1
beq VSSceneDecide_Disconnected

b VSSceneDecide_ConnectionActive

VSSceneDecide_Disconnected:
# Report disconnect
li r3, 1
bl FN_ReportSetCompletion
# We still trigger disconnection calls here because the previous game can end with disconnected message
# while the connection is still technically active
b VSSceneDecide_DisconnectAndNextScene

VSSceneDecide_ConnectionActive:
bl GamePrepData_BLRL
mflr REG_GPD

# Store the result of the last game
load r4, 0x8046b6a0
lbz r3, 0x8(r4)
stb r3, GPDO_LAST_GAME_END_MODE(REG_GPD)

# Get the winner of last game
bl SinglesDetermineWinner
mr REG_WINNER_IDX, r3
cmpwi REG_WINNER_IDX, 0
bge VSSceneDecide_SkipTieHandler # If winner is not -1, it is not a tie

# Here we have a tie, we want to start a new one-stock, 3 min game
lbz r3, GPDO_TIEBREAK_GAME_NUM(REG_GPD)
addi r3, r3, 1
stb r3, GPDO_TIEBREAK_GAME_NUM(REG_GPD)

# Go to the game prep scene, when tiebreak num is greater than zero it will redirect to game
b VSSceneDecide_MoveToGamePrep
VSSceneDecide_SkipTieHandler:

# Here we have a conclusive game. Increment game prep game count and scores
stb REG_WINNER_IDX, GPDO_PREV_WINNER(REG_GPD) # Store winner index

# Set winner ID at game index
lhz r4, GPDO_CUR_GAME(REG_GPD)
addi r4, r4, GPDO_GAME_RESULTS - 1 # Move offset to index in array (cur_game is 1-indexed)
stbx REG_WINNER_IDX, REG_GPD, r4

# Increment game score
addi r3, REG_WINNER_IDX, GPDO_SCORE_BY_PLAYER # Get offset for winner
lbzx r4, REG_GPD, r3
addi r5, r4, 1
stbx r5, REG_GPD, r3 # Store the game score for the winner

# Store stage win
mulli r4, REG_WINNER_IDX, 2
addi r4, r4, GPDO_LAST_STAGE_WIN_BY_PLAYER
lhz r3, MSRB_GAME_INFO_BLOCK + 0xE(REG_MSRB_ADDR) # Load last stage played
sthx r3, REG_GPD, r4

lbz r4, GPDO_MAX_GAMES(REG_GPD)
addi r4, r4, 1
li r3, 2
divwu r4, r4, r3 # Calculate number of wins needed
cmpw r5, r4
bge VSSceneDecide_RankedSetOver

lhz r3, GPDO_CUR_GAME(REG_GPD)
addi r3, r3, 1
sth r3, GPDO_CUR_GAME(REG_GPD)

li r3, 0
stb r3, GPDO_TIEBREAK_GAME_NUM(REG_GPD)

VSSceneDecide_MoveToGamePrep:
# Go back to game prep, there are more games
load r4, 0x80479d30
li r3, 0x06
stb r3, 0x5(r4)
b VSSceneDecide_ModeHandlerEnd

VSSceneDecide_RankedSetOver:
# Report normal set completion
li r3, 0
bl FN_ReportSetCompletion

VSSceneDecide_DisconnectAndNextScene:
# Disconnect from opponent
# Prepare buffer for EXI transfer
li r3, 1
branchl r12, HSD_MemAlloc
mr REG_TXB_ADDR, r3

# Write tx data
li r3, CONST_SlippiCmdCleanupConnections
stb r3, 0(REG_TXB_ADDR)

# Reset connections
mr r3, REG_TXB_ADDR
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

# Allow to return to CSS since ranked set is over

VSSceneDecide_GoToNextScene:
# Go back to CSS
load r4, 0x80479d30
mr r3, REG_NEXT_SCENE
stb r3, 0x5(r4)

VSSceneDecide_ModeHandlerEnd:

###########################################################################
# VSSceneDecide: Handle Non-Ranked Modes
###########################################################################
VSSceneDecide_UpdateWinner:
#Update ISWINNER static bool
lbz r3,MSRB_LOCAL_PLAYER_INDEX(REG_MSRB_ADDR)
bl  CheckIfWonLastGame
stb r3,OFST_R13_ISWINNER(r13)

# Handle case where there's a draw and both players are "winners"
SELECTOR_OVERWRITE:
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_TEAMS
bne SELECTOR_OVERWRITE_NON_TEAMS

# If teams, just overwrite it so that P1 always picks
lbz r3, MSRB_LOCAL_PLAYER_INDEX(REG_MSRB_ADDR)
li r4, 1
cmpwi r3, 0
bne SELECTOR_OVERWRITE_TEAMS_EXEC
li r4, 0
SELECTOR_OVERWRITE_TEAMS_EXEC:
stb r4,OFST_R13_ISWINNER(r13) # 1 for all non-0 players
b SELECTOR_OVERWRITE_END

SELECTOR_OVERWRITE_NON_TEAMS:
.set  REG_Count,20
.set  REG_Winners,21
# Count number of winners
li  REG_Count,0
li  REG_Winners,0
VSSceneDecide_UpdateWinner_Loop:
mr  r3,REG_Count
bl  CheckIfWonLastGame
cmpwi r3,0
beq VSSceneDecide_UpdateWinner_IncLoop
addi  REG_Winners,REG_Winners,1
VSSceneDecide_UpdateWinner_IncLoop:
addi  REG_Count,REG_Count,1
cmpwi REG_Count,4
blt VSSceneDecide_UpdateWinner_Loop
# ensure game only had 1 winner
cmpwi REG_Winners,1
beq SELECTOR_OVERWRITE_END # If only one winner, don't overwrite

# Overwrite to loser to force stage pick from both
li r3,0
stb r3,OFST_R13_ISWINNER(r13)
SELECTOR_OVERWRITE_END:

# For party mode we have a results screen so we dont need gold text
# and also the hack here breaks the results screen
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_PARTY
beq HACK_GOLD_TEXT_END

.set REG_MATCH_END_STRUCT, 20

# Trick gold winner text into working by modifying the values used in calculation
load REG_MATCH_END_STRUCT, 0x80479da4
# Check if this player won and decide how to trick gold text
lbz r3,MSRB_LOCAL_PLAYER_INDEX(REG_MSRB_ADDR)
bl  CheckIfWonLastGame
cmpwi r3, 0
beq HACK_GOLD_TEXT_LOSER

HACK_GOLD_TEXT_WINNER:
li r3, 1
stb r3, 0x0(REG_MATCH_END_STRUCT) # Trick logic into thinking P2 LRAS'd
li r3, 0
stb r3, 0x5D(REG_MATCH_END_STRUCT) # Trick logic into thinking player won
b HACK_GOLD_TEXT_LOSER_END

HACK_GOLD_TEXT_LOSER:
li r3, 0
stb r3, 0x0(REG_MATCH_END_STRUCT) # Trick logic into thinking this player LRAS'd
li r3, 1
stb r3, 0x5D(REG_MATCH_END_STRUCT) # Trick logic into thinking player lost
HACK_GOLD_TEXT_LOSER_END:

# For teams, trick the text into never turning gold (Doesn't work for both LRAS and wins easily)
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_TEAMS
beq HACK_GOLD_TEXT_FORCE_OFF
cmpwi r3, ONLINE_MODE_RANKED
bne HACK_GOLD_TEXT_END # Also prevent gold text in ranked
HACK_GOLD_TEXT_FORCE_OFF:
li r3, 0
stb r3, 0x4(REG_MATCH_END_STRUCT)
HACK_GOLD_TEXT_END:

# Reset CHOSESTAGE bool
li  r3, 0
stb r3, OFST_R13_CHOSESTAGE (r13)

# Prepare to reset RNG seed. This fixes the issue where both clients would
# random the same character following a game

VSSceneDecide_ResetRNG:
# Prepare buffer for EXI transfer
li r3, 4
branchl r12, HSD_MemAlloc
mr REG_TXB_ADDR, r3

# Write tx data
li r3, CONST_SlippiCmdGetNewSeed
stb r3, 0(REG_TXB_ADDR)

# Initiate get new seed command
mr r3, REG_TXB_ADDR
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

# Read back information
mr r3, REG_TXB_ADDR
li r4, 0x4
li r5, CONST_ExiRead
branchl r12, FN_EXITransferBuffer

# Copy RNG seed over
lis r4, 0x804D
lwz r3, 0(REG_TXB_ADDR)
stw r3, 0x5F90(r4) #RNG seed

# Free the TX buffer
mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

# Free the buffer we allocated to get match state
mr r3, REG_MSRB_ADDR
branchl r12, HSD_Free

VSSceneDecide_Exit:
restore
blr
#endregion

#region SplashScenePrep
SplashSceneData:
blrl
.long 0x01780101
.long 0x01FF2121
.long 0xFF2121EE
.long 0x0000EE00
SplashScenePrep:
.set REG_VS_SSS_DATA, 31
.set REG_MSRB_ADDR, 30
.set REG_PLAYER_IDX, 29

backup

# Load match state
li r3, 0
branchl r12, FN_LoadMatchState
mr REG_MSRB_ADDR, r3

lwz	REG_VS_SSS_DATA, -0x77C0 (r13)
addi	REG_VS_SSS_DATA, REG_VS_SSS_DATA, 1424 + 0x8   # adding 0x8 to skip past some unk stuff

# Overwrite SSS Data colors for teams
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_TEAMS
bne SKIP_CHAR_COLOR_OVERWRITE

li REG_PLAYER_IDX, 0

CHAR_COLOR_OVERWRITE_LOOP_START:
# Load the team ID + 1 for team index and character ID to pass to function to get costume ID
mulli r5, REG_PLAYER_IDX, 0x24
addi r3, r5, 0x69
lbzx r3, REG_VS_SSS_DATA, r3 # Loads team ID
addi r3, r3, 1
addi r4, r5, 0x60
lbzx r4, REG_VS_SSS_DATA, r4 # Loads character ID
branchl r12, FN_GetTeamCostumeIndex # Loads costume ID into r3

# Write costume ID 
mulli r4, REG_PLAYER_IDX, 0x24
addi r4, r4, 0x63
stbx r3, REG_VS_SSS_DATA, r4

# Increment port
addi REG_PLAYER_IDX, REG_PLAYER_IDX, 1
cmpwi REG_PLAYER_IDX, 4
blt CHAR_COLOR_OVERWRITE_LOOP_START

SKIP_CHAR_COLOR_OVERWRITE:

#Copy Splash Data
load  r3,0x80490888
bl  SplashSceneData
mflr  r4
li  r5,0x10
branchl r12,memcpy
#Modify Splash Data
load  r4,0x80490888

# Make sure to clear out any special stages setup
li r3, 0
stb r3,-0x1(r4) # match event mode
stb r3,-0x5(r4) # match pvp type (singles, teams, giant, etc...)

.set REG_PLAYER_IDX, 29
.set REG_LEFT_COUNT, 28
.set REG_RIGHT_COUNT, 27
.set REG_LOCAL_PLAYER_IDX, 26
.set REG_LOCAL_PLAYER_TEAM, 25
.set REG_IS_TEAMS, 24

lbz REG_IS_TEAMS, MSRB_GAME_INFO_BLOCK + 0x8(REG_MSRB_ADDR) # load teams flag

# I think the following allows for the splash screen to display more than 2 characters
li r3, 0x2
stb r3,0x2(r4)
li r3, 1
stb r3,0x6(r4)
stb r3,0x7(r4)
stb r3,0x9(r4)
stb r3,0xA(r4)
stb r3,0xC(r4)
stb r3,0xD(r4)
stb r3,0xF(r4)
stb r3,0x10(r4)
stb REG_IS_TEAMS,-0x5(r4) # Conditionally make announcer say "Team..." before the character name

# Load local player idx + team ID
lbz REG_LOCAL_PLAYER_IDX, MSRB_LOCAL_PLAYER_INDEX(REG_MSRB_ADDR)

# ⚠️ A WATCHER is not in the match it is looking at. The split below is
# "me on the left, everybody else on the right", and a watcher sits on a
# port that is deliberately empty - so BOTH players went right and the
# splash read as the two of them being on one team. Stand in for port 0
# FOR THE SPLASH ONLY; the real local index still says 2 everywhere that
# matters, because it decides which port's inputs come off the network.
mulli r3, REG_LOCAL_PLAYER_IDX, 0x24
addi r3, r3, MSRB_GAME_INFO_BLOCK + 0x61 # player type for the local port
lbzx r3, REG_MSRB_ADDR, r3
cmpwi r3, 3
blt VS_SPLASH_LOCAL_IS_PLAYING
li REG_LOCAL_PLAYER_IDX, 0
VS_SPLASH_LOCAL_IS_PLAYING:

li REG_PLAYER_IDX, 0
li REG_LEFT_COUNT, 0
li REG_RIGHT_COUNT, 0
mulli r3, REG_LOCAL_PLAYER_IDX, 0x24
addi r3, r3, MSRB_GAME_INFO_BLOCK+0x69
lbzx REG_LOCAL_PLAYER_TEAM, REG_MSRB_ADDR, r3

VS_SPLASH_CHAR_LOOP:
# Check if player type is set to none, if so skip them
mulli r3, REG_PLAYER_IDX, 0x24
addi r3, r3, 0x61
lbzx r3, REG_VS_SSS_DATA, r3
cmpwi r3, 3
bge VS_SPLASH_CHAR_CONTINUE

# Determine which side this player goes on.
cmpw REG_PLAYER_IDX, REG_LOCAL_PLAYER_IDX
beq VS_SPLASH_CHAR_GO_LEFT
cmpwi REG_IS_TEAMS, 0
bne VS_SPLASH_CHAR_TEAM_CHECK
b VS_SPLASH_CHAR_GO_RIGHT

VS_SPLASH_CHAR_TEAM_CHECK:
mulli r3, REG_PLAYER_IDX, 0x24
addi r3, r3, 0x69
lbzx r3, REG_VS_SSS_DATA, r3
cmpw r3, REG_LOCAL_PLAYER_TEAM
beq VS_SPLASH_CHAR_GO_LEFT
b VS_SPLASH_CHAR_GO_RIGHT

VS_SPLASH_CHAR_GO_LEFT:
# Load char id
mulli r7, REG_PLAYER_IDX, 0x24
addi r5, r7, 0x60
lbzx r5, REG_VS_SSS_DATA, r5
addi r6, REG_LEFT_COUNT, 0x5
stbx r5, r6, r4

# Load char color
addi r5, r7, 0x63
lbzx r5, REG_VS_SSS_DATA, r5
addi r6, REG_LEFT_COUNT, 0xB
stbx r5, r6, r4

addi REG_LEFT_COUNT, REG_LEFT_COUNT, 1
b VS_SPLASH_CHAR_CONTINUE

VS_SPLASH_CHAR_GO_RIGHT:
# Load char id
mulli r7, REG_PLAYER_IDX, 0x24
addi r5, r7, 0x60
lbzx r5, REG_VS_SSS_DATA, r5
addi r6, REG_RIGHT_COUNT, 0x8
stbx r5, r6, r4

# Load char color
addi r5, r7, 0x63
lbzx r5, REG_VS_SSS_DATA, r5
addi r6, REG_RIGHT_COUNT, 0xE
stbx r5, r6, r4

addi REG_RIGHT_COUNT, REG_RIGHT_COUNT, 1

VS_SPLASH_CHAR_CONTINUE:
addi REG_PLAYER_IDX, REG_PLAYER_IDX, 1
cmpwi REG_PLAYER_IDX, 4
blt VS_SPLASH_CHAR_LOOP

# Store side player counts
stb REG_LEFT_COUNT, 0x3(r4)
stb REG_RIGHT_COUNT, 0x4(r4)

# Preload these fighters
load r4,0x80432078
lbz r3, 0x60(REG_VS_SSS_DATA) # load p1 char id
stw r3, 0x14 (r4)
lbz r3, 0x63(REG_VS_SSS_DATA) # load char color
stb r3, 0x18 (r4)
lbz r3, 0x60 + 0x24(REG_VS_SSS_DATA) # load p2 char id
stw r3, 0x1C (r4)
lbz r3, 0x63 + 0x24(REG_VS_SSS_DATA) # load char color
stb r3, 0x20 (r4)

lbz r3, MSRB_GAME_INFO_BLOCK + 0x61 + (0x24*2)(REG_MSRB_ADDR) # Load p3 player type
cmpwi r3, 3 # Check if P3 is set to NONE
bge SKIP_P3_PRELOAD
lbz r3, 0x60 + 0x24*2(REG_VS_SSS_DATA) # load p3 char id
stw r3, 0x24 (r4)
lbz r3, 0x63 + 0x24*2(REG_VS_SSS_DATA) # load char color
stb r3, 0x28 (r4)
SKIP_P3_PRELOAD:

lbz r3, MSRB_GAME_INFO_BLOCK + 0x61 + (0x24*3)(REG_MSRB_ADDR) # Load p4 player type
cmpwi r3, 3 # Check if P4 is set to NONE
bge SKIP_P4_PRELOAD
lbz r3, 0x60 + 0x24*3(REG_VS_SSS_DATA) # load p4 char id
stw r3, 0x2C (r4)
lbz r3, 0x63 + 0x24*3(REG_VS_SSS_DATA) # load char color
stb r3, 0x30 (r4)
SKIP_P4_PRELOAD:

# Preload the stage
lhz r3, 0xE (REG_VS_SSS_DATA)
stw r3, 0xC (r4)
# Queue file loads
branchl r12,0x80018254

li  r3,199
branchl r12,0x80018c2c
li  r3,4
branchl r12,0x80017700

# Clear ssm queue
li	r3, 0x1c  # 0x10 = single player sounds, 0x8 = stage sounds, 0x4 = fighter sounds
branchl	r12, 0x80026F2C

# Load fighters' ssm files
.set REG_COUNT,20
.set REG_CURR,21
li	REG_COUNT, 0
mulli	r0, REG_COUNT, 36
mr REG_CURR, REG_VS_SSS_DATA
add	REG_CURR, REG_CURR, r0
CSSSceneDecide_SSMLoop:
# Get fighter's external ID
branchl r12,FN_GetFighterNum
lbz	r4, 0x0060 (REG_CURR)
extsb	r4, r4
cmpw r4,r3
beq CSSSceneDecide_SSMIncLoop
# Get fighter's ssm ID
li r3,0   # fighter
# r4 already contains fighter index
branchl r12,FN_GetSSMIndex
branchl r12,FN_RequestSSM   # queue it
CSSSceneDecide_SSMIncLoop:
addi	REG_COUNT, REG_COUNT, 1
cmpwi	REG_COUNT, 6
addi	REG_CURR, REG_CURR, 36
blt+	 CSSSceneDecide_SSMLoop
# Get stage's ssm file index
lhz r3, 0xE (REG_VS_SSS_DATA)
branchl r12,0x8022519c  # get internal ID
mr r4,r3  # stage index
li r3,1   # stage
branchl r12,FN_GetSSMIndex
branchl r12,FN_RequestSSM   # queue it
# set to load
branchl r12, 0x80027168

restore
blr
#endregion
#region SplashSceneDecide
SplashSceneDecide:
backup

# This will cause the next scene to be VS mode
load r4, 0x80479d30
li r3, 0x03
stb r3, 0x5(r4)

restore
blr
#endregion
#region SplashSceneInit
SplashSceneInit:
.set  REG_MSRB_ADDR,31
.set  REG_VS_SSS_DATA,30
backup

# Get match state info
li r3, 0
branchl r12, FN_LoadMatchState
mr REG_MSRB_ADDR, r3

# Copy Match Info. In-Game scene prep function will copy this data into the In-Game
# minor scene data (0x10), which ultimately gets used.
lwz	REG_VS_SSS_DATA, -0x77C0 (r13)
addi	REG_VS_SSS_DATA, REG_VS_SSS_DATA, 1424 + 0x8   # adding 0x8 to skip past some unk stuff
mr  r3,REG_VS_SSS_DATA
addi r4,REG_MSRB_ADDR, MSRB_GAME_INFO_BLOCK    #
li  r5,0x60 + (0x24*6)  #match data + player data
branchl r12,memcpy

# Adjust null ID
mr  r3,REG_VS_SSS_DATA
branchl r12,FN_AdjustNullID

# Free the buffer we allocated to get match settings
mr r3, REG_MSRB_ADDR
branchl r12, HSD_Free

restore
blr
#endregion

################################################################################
# Function: SinglesDetermineWinner
# ------------------------------------------------------------------------------
# Description: Designed to be used only when playing online (only works with
# ports 1 + 2). Will output the winner of the match or -1 if it's a tie.
# 
# Does not handle LRAS
# ------------------------------------------------------------------------------
# Output:
# r3: winnderIndex # Index of the winner, -1 if tie
################################################################################
SinglesDetermineWinner_BLRL:
blrl
.set REG_MATCH_END, 31
.set REG_MATCH_END_P1, 30
.set REG_MATCH_END_P2, 29
.set REG_TEMP_VAR, 27
SinglesDetermineWinner:
backup

load REG_MATCH_END, 0x80479da4

# The following may be needed if we add LGL but are not needed right now
# addi REG_MATCH_END_P1, REG_MATCH_END, 0x58 # Start of player array
# addi REG_MATCH_END_P2, REG_MATCH_END_P1, 0xA8

lbz r3, 0x4(REG_MATCH_END)
cmpwi r3, 1
beq SinglesDetermineWinner_HANDLE_TIMEOUT
cmpwi r3, 2
beq SinglesDetermineWinner_HANDLE_COMPLETION

# We can only handle GAME and TIME atm. For LRAS (or something else?), return a tie
b SinglesDetermineWinner_TIE

SinglesDetermineWinner_HANDLE_TIMEOUT:
# Handle ledge grab limit
li r3, 0
branchl r12, 0x80040af0 # PlayerBlock_GetCliffhangerStat
mr REG_TEMP_VAR, r3
li r3, 1
branchl r12, 0x80040af0 # PlayerBlock_GetCliffhangerStat
cmpwi REG_TEMP_VAR, LGL_LIMIT
ble SinglesDetermineWinner_CHECK_LGL_LOSS
cmpwi r3, LGL_LIMIT
bgt SinglesDetermineWinner_LGL_EXIT # If we branch here both players have more than 45 so ignore LGL
SinglesDetermineWinner_CHECK_LGL_LOSS:
cmpwi REG_TEMP_VAR, LGL_LIMIT
bgt SinglesDetermineWinner_P2_WIN # If P1 has more than 45 ledge grabs, P2 wins
cmpwi r3, LGL_LIMIT
bgt SinglesDetermineWinner_P1_WIN # If P2 has more than 45 ledge grabs, P1 wins
SinglesDetermineWinner_LGL_EXIT:

li r3, 0
branchl r12, 0x80033bd8 # PlayerBlock_LoadStocksLeft
mr REG_TEMP_VAR, r3
li r3, 1
branchl r12, 0x80033bd8 # PlayerBlock_LoadStocksLeft
cmpw REG_TEMP_VAR, r3
bgt SinglesDetermineWinner_P1_WIN
blt SinglesDetermineWinner_P2_WIN

li r3, 0
branchl r12, 0x800342b4 # PlayerBlock_LoadDamage
mr REG_TEMP_VAR, r3
li r3, 1
branchl r12, 0x800342b4 # PlayerBlock_LoadDamage
cmpw REG_TEMP_VAR, r3
blt SinglesDetermineWinner_P1_WIN
bgt SinglesDetermineWinner_P2_WIN

# We only get here if stock and percent is the same, if so, it's a tie
b SinglesDetermineWinner_TIE

SinglesDetermineWinner_HANDLE_COMPLETION:
# Here we check who won by looking at stock counts
li r3, 0
branchl r12, 0x80033bd8 # PlayerBlock_LoadStocksLeft
cmpwi r3, 0
bne SinglesDetermineWinner_P1_WIN

li r3, 1
branchl r12, 0x80033bd8 # PlayerBlock_LoadStocksLeft
cmpwi r3, 0
bne SinglesDetermineWinner_P2_WIN

# If we get here, both players have zero stocks which indicates a same-frame double KO, it's a tie
b SinglesDetermineWinner_TIE

SinglesDetermineWinner_P1_WIN:
li r3, 0
b SinglesDetermineWinner_RESTORE_AND_EXIT
SinglesDetermineWinner_P2_WIN:
li r3, 1
b SinglesDetermineWinner_RESTORE_AND_EXIT
SinglesDetermineWinner_TIE:
li r3, -1
SinglesDetermineWinner_RESTORE_AND_EXIT:
restore
blr

#region CheckIfWonLastGame
CheckIfWonLastGame:
.set MatchEndStruct,31
.set MatchEndPlayerStruct,30
.set PlayerSlot,29

backup

mr  PlayerSlot,r3
load  MatchEndStruct,0x80479da4
mulli MatchEndPlayerStruct,PlayerSlot,0xA8
add   MatchEndPlayerStruct,MatchEndPlayerStruct,MatchEndStruct

#Check if last game data exists
  lbz r3,0x4(MatchEndStruct)
  cmpwi r3,0x0
  beq  CheckIfWonLastGame_DidNotWin

#Check if last game was same Mode (Teams/FFA)
  load r3,0x8046b6a0
  lbz r3,0x24D0(r3)
  lbz r4,0x6(MatchEndStruct)
  cmpw r3,r4
  bne CheckIfWonLastGame_DidNotWin

#Check if player partook in last game
  lbz r3,0x58(MatchEndPlayerStruct)
  cmpwi r3,3
  beq CheckIfWonLastGame_DidNotWin

#Check if last game was an LRA Start
  lbz r3,0x4(MatchEndStruct)
  cmpwi r3,0x7
  bne CheckIfWonLastGame_CheckForTeams
  #Check if this was a team LRA Start
    lbz r3,0x6(MatchEndStruct)
    cmpwi r3,0x1
    bne CheckIfWonLastGame_FFA_LRAStart
    CheckIfWonLastGame_Team_LRAStart:
    #Check who LRA started
      lbz r3,0x0(MatchEndStruct)
    #Get his team ID
      mulli r3,r3,0xA8
      add   r3,r3,MatchEndStruct
      lbz   r3,0x5F(r3)
    #Get current players team ID
      lbz   r4,0x5F(MatchEndPlayerStruct)
    #Check If Same Team
      cmpw  r3,r4
      beq CheckIfWonLastGame_DidNotWin
      b CheckIfWonLastGame_Won

    CheckIfWonLastGame_FFA_LRAStart:
    #Check who LRA started
      lbz r3,0x0(MatchEndStruct)
      #If this player did, return 0
        cmpw r3,PlayerSlot
        beq CheckIfWonLastGame_DidNotWin
        b CheckIfWonLastGame_Won

CheckIfWonLastGame_CheckForTeams:
#Check if Teams Match
  lbz r3,0x6(MatchEndStruct)
  cmpwi r3,0x1
  bne CheckIfWonLastGame_FFA
  #If so find winning team
    mr  r3,MatchEndStruct
    branchl r12, MatchEnd_GetWinningTeam
  #Check this players team
    lbz   r4,0x5F(MatchEndPlayerStruct)
  #If this player was on winning team, return 1, if not return 0
    cmpw r3,r4
    beq CheckIfWonLastGame_Won
    b CheckIfWonLastGame_DidNotWin

CheckIfWonLastGame_FFA:
#Check If Player Won
  lbz   r3,0x5D(MatchEndPlayerStruct)
   # . if so return 1, if not return 0
   cmpwi  r3,0
   beq  CheckIfWonLastGame_Won
   b CheckIfWonLastGame_DidNotWin

CheckIfWonLastGame_DidNotWin:
li  r3,0
b 0x8
CheckIfWonLastGame_Won:
li  r3,1

restore
blr
#endregion

################################################################################
# Routine: RoomSlpCSSStrings
# ------------------------------------------------------------------------------
# The file and the symbol inside it, laid out the way SceneLoadCSS.asm lays them
# out: the name at +0 and the symbol at +11, so one pointer reaches both.
################################################################################
RoomSlpCSSStrings:
blrl
.string "slpCSS.dat"
.string "slpCSS"
.align 2

GamePrepScenePrep:
.set REG_GPD, 31
.set REG_ROOM_STR, 30
.set REG_ROOM_ARC, 29
.set REG_ROOM_SYM, 28
.set REG_ROOM_CSSDT, 27

backup

lwz REG_GPD, 0x10(r3) # Grabs load data

################################################################################
# The draft wants the character select's archive
################################################################################
# GameSetup.dat builds its models out of it -
#
#     r9  = *CSSDT_BUF_ADDR        the character select's data table
#     r29 = *(r9 + 4)              this pointer
#     r9  = *(r29 + 0x10)          a JOBJ descriptor
#
# at code+0x38e4 - and only SceneLoad_CSS ever fills it in, because Slippi only
# reaches this screen between games of a set, after that scene has run. A room
# comes straight from its own queue, so it arrives with the field holding
# whatever was last in the buffer, and both clients die on it.
#
# ⚠️ That is the "Invalid read from 0x30310012" crash, and the number is the
# clue: *CSSDT_BUF_ADDR was NULL, so reading the archive pointer at +4 read
# address 0x00000004 instead - which is "01" and the disc version bytes out of
# GALE01's OWN HEADER. The pointer that killed both clients was the disc label.
#
# So do what that scene does: load the file, ask the archive for the symbol,
# write it down. HERE and not in the room module, because a file loaded from a
# scene lives on that scene's heap and the room's is about to be freed. This
# runs inside the draft's own scene, before its module's Load.
#
# Not conditional on the field being empty - it is not empty when it is wrong,
# it is stale.
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
bne RoomSlpCSS_SKIP

# The table itself first, since a room has never been to the character select.
loadwz REG_ROOM_CSSDT, CSSDT_BUF_ADDR
cmpwi REG_ROOM_CSSDT, 0
bne RoomSlpCSS_HAVE_TABLE

li r3, CSSDT_SIZE
branchl r12, HSD_MemAlloc
mr REG_ROOM_CSSDT, r3
li r4, CSSDT_SIZE
branchl r12, Zero_AreaLength

load r3, CSSDT_BUF_ADDR
stw REG_ROOM_CSSDT, 0(r3)

li r3, MSRB_SIZE
branchl r12, HSD_MemAlloc
stw r3, CSSDT_MSRB_ADDR(REG_ROOM_CSSDT)

RoomSlpCSS_HAVE_TABLE:
cmpwi REG_ROOM_CSSDT, 0
beq RoomSlpCSS_SKIP

# And then the archive, the same two calls the character select makes.
bl RoomSlpCSSStrings
mflr REG_ROOM_STR

mr r3, REG_ROOM_STR
branchl r12, 0x80016be0     # File_Load
mr REG_ROOM_ARC, r3
cmpwi REG_ROOM_ARC, 0
beq RoomSlpCSS_SKIP

mr r3, REG_ROOM_ARC
addi r4, REG_ROOM_STR, 11   # the symbol, just past the file name
branchl r12, 0x80380358     # File_GetSymbol
mr REG_ROOM_SYM, r3
cmpwi REG_ROOM_SYM, 0
beq RoomSlpCSS_SKIP

stw REG_ROOM_SYM, CSSDT_SLPCSS_ADDR(REG_ROOM_CSSDT)

RoomSlpCSS_SKIP:

# Check if this is a tiebreak. If it is a tiebreak, we dont want to invalidate since the same
# characters will be loaded
lbz r3, GPDO_TIEBREAK_GAME_NUM(REG_GPD)
cmpwi r3, 0
bne SKIP_PRELOAD_INVALIDATE

# Invalidate pre-load cache otherwise changing one character mid-set crashes
branchl r12, 0x800174bc
SKIP_PRELOAD_INVALIDATE:

restore
blr

GamePrepSceneDecide:
.set REG_GPD, 31
.set REG_MSRB_ADDR, 30

backup

lwz REG_GPD, 0x10(r3) # Grabs load data

# Get match state info
li r3, 0
branchl r12, FN_LoadMatchState
mr REG_MSRB_ADDR, r3

# If connection is active, do the normal execution
lbz r3, MSRB_CONNECTION_STATE(REG_MSRB_ADDR)
cmpwi r3, MM_STATE_CONNECTION_SUCCESS
beq GamePrepSceneDecide_ExecNormal

# Here we have disconnected from opponent, go back to CSS

# In theory this should have already been sent by the game setup scene but there's
# no harm in sending a duplicate and this covers our bases in the case of a poorly timed
# disconnect, such as maybe right before the game tries to load
li r3, 1
bl FN_ReportSetCompletion

# Go back to CSS - or, in a room, back to the ROOM.
#
# ⚠️ The character select is not a place a Rooms player belongs. They never
# passed through it on the way here: a room goes room -> draft -> game. Sent
# there after an opponent walks out, they land on a screen with nothing to do
# and an error on it, and the only way out is the redirect in CSSSceneDecide
# firing when they leave - so the error is seen every time.
#
# The room is where they came from and where the queue still is.
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
bne GamePrepSceneDecide_DiscToCSS
load r4, 0x80479d30
li r3, MINOR_ROOM + 1
stb r3, 0x5(r4)
b GamePrepSceneDecide_RestoreAndExit

GamePrepSceneDecide_DiscToCSS:
load r4, 0x80479d30
li r3, 0x01
stb r3, 0x5(r4)
b GamePrepSceneDecide_RestoreAndExit

GamePrepSceneDecide_ExecNormal:
# Check if there was a tie last game and a tiebreak is needed
lbz r3, GPDO_TIEBREAK_GAME_NUM(REG_GPD)
cmpwi r3, 0
beq GamePrepSceneDecide_DisplaySplash

# On tiebreak, go right back into VS scene
load r4, 0x80479d30
li r3, 0x03
stb r3, 0x5(r4)
b GamePrepSceneDecide_RestoreAndExit

GamePrepSceneDecide_DisplaySplash:
bl  SplashSceneInit

# This will cause the next scene to be the splash screen
load r4, 0x80479d30
li r3, 0x05
stb r3, 0x5(r4)

GamePrepSceneDecide_RestoreAndExit:
restore
blr

################################################################################
# Room: scene prep and decide
################################################################################
# Ask for the two fighters' files, and set up the struct the splash builds from.
#
# This is why the room sat on NOW LOADING. A fighter's model is a file that
# comes off the disc across frames, and a scene has to REQUEST it - the request
# table is at 0x80432078, a char id and a costume per player, and Preload_Update
# turns whatever is in it into actual loads. An empty prep asks for nothing, so
# the splash waits on files nobody ordered and says so, for ever.
#
# The old branch pumped Preload_Update every frame and recorded that it "changes
# nothing". That was true and the conclusion was wrong: it was pumping an empty
# queue. The missing half was never the pump, it was the order.
#
# All of this is SplashScenePrep's own preload block a few hundred lines up,
# with the characters hardcoded instead of read out of the match - there is no
# match yet. When there is, these two come from the room's state and nothing
# else here changes.
# INTERNAL character ids, not external ones - which is why asking for "Fox and
# Marth" has been putting DK and Zelda on screen this whole time. Internal
# order runs Falcon, DK, Fox, Game & Watch, Kirby, Bowser, Link, Luigi, Mario,
# Marth ... Zelda at 18. The screen was right and the comment was wrong.
#
# Worth keeping for another reason: Game & Watch is internal 3, and he is drawn
# flat solid black. A character as a black shape is the one way this scene can
# put an opaque rectangle anywhere, since nothing here can draw a filled quad.

# What gets BUILT when nobody has chosen yet. Not what gets SHOWN - an idle
# room draws no fighters, and room_show_fighters hides these two by flag once
# they exist.
#
# ⛔ Do NOT use 26 here to build nothing instead. It does build nothing, which
# is the trouble: the camera goes with it. "banded 0 cam", no classes 20 or 21,
# and the room is black - the text cannot draw either, because there is nothing
# left to draw it through. The scene has to be built in full and then covered.
.set ROOM_EMPTY_CHAR_L, 1     # Donkey Kong
.set ROOM_EMPTY_CHAR_R, 18    # Zelda
.set ROOM_CHAR_GAMEWATCH, 3   # flat black, if a cover is ever wanted
.set ROOM_EMPTY_STAGE, 0x1F  # Battlefield, as the empty backdrop

# What CMD_ROOM_STATE hands back. ⚠️ Mirrors the layout in
# Rooms/Modules/include/rooms.h - change both or this reads the wrong bytes.
.set ROOMS_STATE_SIZE,       510   # 12 header + 14 names of 32 + 20 opp code
                                   #  + 14 crowns + 8 room code + 8 passcode
.set ROOMS_STATE_HOST_CHAR,  0x04
.set ROOMS_STATE_HOST_COL,   0x05
.set ROOMS_STATE_GUEST_CHAR, 0x06
.set ROOMS_STATE_GUEST_COL,  0x07
.set ROOMS_STATE_STAGE,      0x08
.set ROOMS_NOT_PICKED,       0xFF

RoomScenePrep:
# ⚠️ 544 of free space, for the room state read below - and `restore` has to be
# told the same number or it unwinds the wrong amount of stack.
.set ROOM_PREP_FRAME, 544
backup ROOM_PREP_FRAME

################################################################################
# Ask Dolphin what the pair are playing
################################################################################
# The band used to be two placeholders. It is built HERE, because a fighter is
# a file read off the disc across frames and this is the scene's one chance to
# ask for it - so the answer has to be in hand before anything below runs.
#
# ⚠️ The room re-enters its own scene when the picks change. That is what makes
# this work at all: the pair draft while everyone else is already sitting in
# the room, long after this ran, so the only way to show what they chose is to
# come back through here. See room_think.
#
# A 32-byte aligned scratch inside this frame's free space - EXI transfers by
# DMA and an unaligned buffer is a corrupt read rather than a failed one.
addi r31, r1, 0x8 + 31
rlwinm r31, r31, 0, 0, 26

li r3, CONST_SlippiCmdRoomState
stb r3, 0x0(r31)
mr r3, r31
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

# ⚠️ All of it, not just the header. Dolphin answers from a queue and a short
# read leaves the rest of it there for whoever asks next.
mr r3, r31
li r4, ROOMS_STATE_SIZE
li r5, CONST_ExiRead
branchl r12, FN_EXITransferBuffer

# ⚠️ Read into NON-VOLATILE registers, and after the calls above rather than
# before - everything below still has two library calls to get through.
lbz r26, ROOMS_STATE_HOST_CHAR(r31)
lbz r27, ROOMS_STATE_HOST_COL(r31)
lbz r28, ROOMS_STATE_GUEST_CHAR(r31)
lbz r29, ROOMS_STATE_GUEST_COL(r31)
lbz r30, ROOMS_STATE_STAGE(r31)

# Anything not yet chosen and the placeholders stand in for all of it, rather
# than half a real match beside half an invented one.
cmpwi r26, ROOMS_NOT_PICKED
beq RoomScenePrep_NO_PICKS
cmpwi r28, ROOMS_NOT_PICKED
beq RoomScenePrep_NO_PICKS
cmpwi r30, ROOMS_NOT_PICKED
bne RoomScenePrep_HAVE_PICKS

RoomScenePrep_NO_PICKS:
li r26, ROOM_EMPTY_CHAR_L
li r27, 0
li r28, ROOM_EMPTY_CHAR_R
li r29, 0
# ⚠️ A stage is still ordered even with nobody on it. It is the backdrop, and
# more to the point NOW LOADING is the splash saying it is still waiting for
# files - ask for no stage and it waits for ever.
li r30, ROOM_EMPTY_STAGE
RoomScenePrep_HAVE_PICKS:


# The splash reads a struct it does not initialise, so the template goes in
# first - +0x08 through +0x0A are fields whose meaning is not known here, and
# leaving them as whatever the last scene left behind is how a builder ends up
# reading a costume of 0xEE.
load  r3,0x80490888
bl  SplashSceneData
mflr  r4
li  r5,0x10
branchl r12,memcpy

load  r4,0x80490888

# No special stage rules, and not a teams match.
li r3, 0
stb r3,-0x1(r4)             # match event mode
stb r3,-0x5(r4)             # match pvp type

# One character a side. The layout is the splash prep's, counted off its own
# stores: counts at +3 and +4, then THREE left char ids at +5 and three right
# at +8, with their costumes at +0xB and +0xE.
#
# Worth knowing, because the room had this wrong: +0x10 and +0x11 of the minor
# data - which is r4+8 and r4+9 - are the first two RIGHT slots, not "character
# one and character two". Writing a pair there put both fighters on the same
# side of a screen that had been told only one of them was there.
li r3, 1
stb r3, 0x3(r4)             # left count
stb r3, 0x4(r4)             # right count

stb r26, 0x5(r4)            # left slot 0
stb r27, 0xB(r4)            # ...its costume

stb r28, 0x8(r4)            # right slot 0
stb r29, 0xE(r4)            # ...its costume

# Order the files.
load r4, 0x80432078
stw r26, 0x14(r4)
stb r27, 0x18(r4)
stw r28, 0x1C(r4)
stb r29, 0x20(r4)

# And the stage, which was left out of the first version of this on purpose -
# fewer things in flight while the fighters were the question.
#
# NOW LOADING is not decoration. It is the splash saying it is still waiting for
# files, which it has been, because the room ordered two fighters and nothing
# else. The splash's own prep asks for the stage here too, out of the stage
# select data; the room asks Dolphin instead, and falls back to Battlefield
# when the pair have not chosen one.
stw r30, 0xC(r4)

# Queue the loads. The three calls are the splash prep's, in its order; only
# the first of them has a name in the symbol file.
branchl r12,0x80018254      # Preload_Update
li  r3,199
branchl r12,0x80018c2c
li  r3,4
branchl r12,0x80017700

restore ROOM_PREP_FRAME
blr

# The draft, and what it needs before it can be entered.
#
# The module asks by writing the pending-minor byte, and this notices what was
# asked for. That byte is one-based, so the draft - minor 5 - asks as 6.
.set ROOM_PENDING_DRAFT, MINOR_GAMESETUP + 1
.set ROOM_PENDING_SPLASH, MINOR_SPLASH + 1
.set ROOM_WATCHER_PORT, 2

RoomSceneDecide:
.set REG_ROOM_GPD, 31

backup

################################################################################
# Give the 1P port back, if a watch borrowed it
################################################################################
# ⚠️ A watch points -0x5108(r13) at a port that is NOT in the match, and on
# the room's path to a game nothing ever writes it again. The character
# select's A press is what normally sets it and a room does not go through
# that screen - so after watching, the watcher's OWN next match read an
# empty port and their controller did nothing at all.
#
# Done here, before anything decides where to go, so it holds for every way
# out of the room. The watch path below borrows it again straight after.
fetchOnlineStaticDataPtr r4
lbz r5, OSD_WATCH_PORT_BORROWED(r4)
cmpwi r5, 0
beq RoomSceneDecide_PORT_NOT_BORROWED
lbz r5, OSD_WATCH_SAVED_PORT(r4)
stb r5, -0x5108(r13)
li r5, 0
stb r5, OSD_WATCH_PORT_BORROWED(r4)
RoomSceneDecide_PORT_NOT_BORROWED:

load r4, 0x80479d30
lbz r3, 0x5(r4)

################################################################################
# A watcher, going straight to the match
################################################################################
# It has nothing to pick and no way to advance a screen that wants a pick, so
# the room skips it past the character select entirely. What that screen would
# have done is copy Dolphin's match block into the scene, and for a watcher
# Dolphin has already filled that block in from the stream - so the splash's own
# init is the whole of what is owed, and it has to run before the scene loads.
cmpwi r3, ROOM_PENDING_SPLASH
bne RoomSceneDecide_NOT_SPLASH

# ⚠️ Say which port the local inputs come from, because nothing else will.
#
# InitOnlinePlay reads the 1P port out of -0x5108(r13) and makes it the game's
# input source. That byte is written by CSS_StoreSinglePlayerPortNumber, from
# the character select's A press - and a watcher never presses A, so on this
# path it holds whatever happened to be there.
#
# If it names a port that IS in the match, Melee takes a neutral controller for
# a player who is actually being fed, and simulates a DIFFERENT match: the clock
# stays right and the damage does not. That is the divergence the old build
# died of, and it is why going through the character select used to work - it
# set this byte on the way past.
#
# Port 2 is not in the match. Its neutral controller moves nothing.
#
# ⚠️ Kept first, because it has to go back. See the restore at the top of
# this function - without it, watching once left this client unable to
# play for the rest of the session.
fetchOnlineStaticDataPtr r4
lbz r5, -0x5108(r13)
stb r5, OSD_WATCH_SAVED_PORT(r4)
li r5, 1
stb r5, OSD_WATCH_PORT_BORROWED(r4)

li r3, ROOM_WATCHER_PORT
stb r3, -0x5108(r13)

bl SplashSceneInit
b RoomSceneDecide_EXIT

RoomSceneDecide_NOT_SPLASH:
cmpwi r3, ROOM_PENDING_DRAFT
bne RoomSceneDecide_EXIT

################################################################################
# Fill in the draft's own data, because nothing else will
################################################################################
# Slippi only ever reaches this screen from the VS scene's decide, BETWEEN games
# of a set, so it helps itself to whatever that path has already left lying
# around. A room arrives from its own queue with none of it.
#
# ⚠️ GPDO_CUR_GAME is 2, not 1. This is the between-games screen: told it is
# game one it has nothing to counterpick from and skips straight past itself,
# which is a draft that never appears. A room's first game has no previous
# result to show - that is something to fill in later, not a reason to avoid
# the screen.
bl GamePrepData_BLRL
mflr REG_ROOM_GPD

mr r3, REG_ROOM_GPD
li r4, GPDO_SIZE
branchl r12, Zero_AreaLength

# ⚠️ Zeroed just now, so the winner callback has to go back in. Without it the
# set has no way to work out who won a game.
bl SinglesDetermineWinner_BLRL
mflr r3
stw r3, GPDO_FN_COMPUTE_RANKED_WINNER(REG_ROOM_GPD)

li r3, 3
stb r3, GPDO_MAX_GAMES(REG_ROOM_GPD)
li r3, 2
sth r3, GPDO_CUR_GAME(REG_ROOM_GPD)
li r3, 0
stb r3, GPDO_TIEBREAK_GAME_NUM(REG_ROOM_GPD)
stb r3, GPDO_COLOR_BAN_ACTIVE(REG_ROOM_GPD)

# EXPERIMENT. Who bans first.
#
# GPDO_PREV_WINNER is the previous game's winner, and Melee counterpick rules
# say the winner bans - so this should be the byte that decides it. Nothing in
# this repo READS it; only GameSetup.dat does, and that is a shipped binary with
# no source here, so it cannot be read the way the DOL can. Zeroing it with the
# rest of the struct is why port 0 has always banned first.
#
# Hardcoded to 1 to find out, because the alternative was guessing and paying
# for a 40-minute Dolphin build to find out the guess was wrong. If the OTHER
# player bans after this, the byte is confirmed and the real version can be
# built: the room's rule is that the longest-standing member stands in for the
# winner, for a first game and for a game whose winner has left, and Dolphin
# already knows which of the pair that is - State::is_host. It needs a byte in
# the room state payload to say so, which is the Dolphin change this is meant
# to de-risk.
#
# â ï¸ REMOVE THIS once the answer is in. Left alone it hands the ban to
# whoever is port 1, which is no more correct than port 0 was.
li r3, 1
stb r3, GPDO_PREV_WINNER(REG_ROOM_GPD)

RoomSceneDecide_EXIT:
restore
blr


################################################################################
# Practice. Melee's own training scenes, run as minors of the online major.
#
# ⚠️ Every one of these writes the scene controller's pending-minor byte, which
# is ONE-BASED - the id plus one. Off by one lands on the neighbouring scene.
################################################################################

# Training's own prep builds the match its minor data describes.
RoomTrainScenePrep:
backup
branchl r12, ScenePrep_TrainingMode_InGame
restore
blr

# Leaving training goes back to the room, never out of the major. The room is
# where the queue is, and the whole point of practising is that you are still
# in it.
RoomTrainSceneDecide:
backup
load r4, 0x80479d30
li r3, MINOR_ROOM + 1
stb r3, 0x5(r4)
restore
blr

# The character select comes first - a training match needs a character in it,
# and this is where one comes from. MajorSetup_TrainingMode before the prep,
# because the prep reads what it sets up.
RoomTrainCSSPrep:
backup
mr r31, r3
branchl r12, MajorSetup_TrainingMode
mr r3, r31
branchl r12, ScenePrep_TrainingMode_CSS
restore
blr

# Forward to the stage select, or back to the room if they backed out. ⚠️ The
# back path also has to say the major is not going anywhere: without the write
# to 0x1, backing out of practice leaves the online major entirely and lands on
# the main menu.
RoomTrainCSSDecide:
backup
mr r31, r3
branchl r12, SceneDecide_TrainingMode_CSS
mr r3, r31
branchl r12, GetMinorSceneData2
lbz r0, 0x3(r3)
load r4, 0x80479d30
cmpwi r0, TRAIN_CSS_BACKED_OUT
beq RoomTrainCSSDecide_BACK
li r3, MINOR_TRAIN_SSS + 1
b RoomTrainCSSDecide_SET
RoomTrainCSSDecide_BACK:
li r3, ONLINE_MAJOR_ID
stb r3, 0x1(r4)             # nothing is leaving this major
li r3, MINOR_ROOM + 1
RoomTrainCSSDecide_SET:
stb r3, 0x5(r4)
restore
blr

# Stage picked goes to training; backing out goes to the character select.
RoomTrainSSSDecide:
backup
mr r31, r3
branchl r12, SceneDecide_TrainingMode_SSS
mr r3, r31
branchl r12, GetMinorSceneData2
lbz r0, 0x4(r3)
load r4, 0x80479d30
cmpwi r0, 0
beq RoomTrainSSSDecide_BACK
li r3, MINOR_TRAIN + 1
b RoomTrainSSSDecide_SET
RoomTrainSSSDecide_BACK:
li r3, MINOR_TRAIN_CSS + 1
RoomTrainSSSDecide_SET:
stb r3, 0x5(r4)
restore
blr

Injection_Exit:
#Exit Scene
  restore
  li  r3,ExitSceneID
  stb r3,0x0(r30)
