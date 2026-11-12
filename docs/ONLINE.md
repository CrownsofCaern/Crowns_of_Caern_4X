# Online play

Several people play one game, each on their own computer. One computer **hosts**; the others **join** with
its address. Play is turn by turn: whoever is to move plays the whole turn, and **End Turn** hands the game
on. Computer players move on the host between human turns.

## Play over the internet with Tailscale

Most home routers block incoming connections. [Tailscale](https://tailscale.com) (free for personal use)
connects the computers directly, so nobody needs router settings or port forwarding.

1. Everyone installs Tailscale and signs in.
2. The host shares their computer with the others in the Tailscale admin console (**Share** on the
   machine), or everyone joins the same tailnet.
3. The host's Tailscale address (`100.x.y.z`) is shown in the Tailscale app, and in the game once it hosts.
4. The first time the game hosts, macOS or Windows may ask whether it may accept incoming connections:
   allow it.

[ZeroTier](https://www.zerotier.com) works the same way. On one local network no extra software is needed:
join with the host's local address.

## Host a game

1. Start a **New Game** with two or more **Human** player slots, or **Load Game** (any save: a hot-seat game,
   or an online game saved earlier).
2. Open the menu (`Esc`), choose **Online Game**, enter your name and press **Host this game**.
3. In the player list, **Take** the player you play. The game uses port 24680 (UDP).

## Join a game

1. Choose **Online Game** on the title screen, enter your name and the host's address, then **Join**.
2. **Take** a free player. You can join at any time, also in the middle of a game.

Every computer needs the same version of the game; the host refuses a join from another version.

## While you play

- While another person moves, your map stays hidden and the online panel shows whose turn it is.
- One person may play several players. A player whose person has left shows "(away)" and can be taken
  over, for example by the host for one turn.
- A battle against your heroes or towns during someone else's turn is reported at the start of your turn.
  Your heroes defend without the flee choice (as they do against another human in hot-seat).

## Save and resume

Every computer keeps the latest turn under **Load Game** as an **Online** slot, updated after every turn.
To continue later, any of the players loads that slot and hosts it again; the others join and take their
players again (their names are remembered in the save, so they get the same players back).

## How it works (for developers)

- `src/game/online_match.gd` (headless): seats (a player's `seat` is the name of the person playing it), the
  match id, checking a handed-over save (`check_handoff`), computer turns on the host, packing saves.
- `src/net/net_session.gd`: ENet host/join, seats via the host, turn handoff. It only moves whole saves; the
  host's copy is the one that counts, and the host sends it to everyone after every turn.
- `src/ui/online_panel.gd`: the connect page and the match page; `adventure_screen.gd` switches between
  playing and waiting.
- Saves from version 24 carry `online` (`{match_id}`) and the players' `seat`.
- Tests: `tests/unit/test_online_match.gd` and `tests/integration/online_loopback.gd` (two screens playing over
  `127.0.0.1`).
