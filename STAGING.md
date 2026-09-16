# Staging

Private. Nothing here is presented to anyone.

Work is proven here first - it builds, it runs, a human has seen it behave -
and only then do the clean commits go to
`attunegames/slippi-ssbm-asm` on `feature/rooms`, which is the branch that
stays presentable.

`feature/rooms` starts at Slippi's own commit
`fcf47f10dc244152c2ebaa3a9dec142ea42243b7`, identical tree and identical SHA,
so `git diff upstream/master` there shows exactly what we added and nothing
else. Keeping it that way is the whole point of this repo existing.
