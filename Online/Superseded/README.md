# Superseded

`InitOnlinePlay.asm` injects at `0x8016e748`. So does Slippi's playback code
`Playback/Core/StartMelee/RestoreGameInfo.asm`, and Peppy builds one codeset
that has to do both.

`Peppy/Playback/StartMelee.asm` is the merge: it runs the replaced instruction
once, then dispatches on the scene to whichever body applies. Both bodies are
copied verbatim from the originals.

This file is kept, unmodified, as the source of truth for the online half of
that merge. It is not injected - nothing in `netplay.json` points at this
folder. If you change it, regenerate the merge.
