# sban

This mod is based on the concepts introduced by xban2, expanding on them
by using an sql db instead of a serialised table file. Resulting in an
improvement in the robustness of the data, offering the accessibility of
connecting to the db via SSH with your favourite db management gui, automatic
ban management and the capability to ban an unknown player with server
privilege. Currently the add and update transactions are coded without
locks so it's not recommended to write to the db whilst minetest is using it.
Reading the db shouldn't be an issue.

#### INSTALLATION

sban requires lsqlite3(https://github.com/LuaDist/lsqlite3)

If you have luarocks(https://luarocks.org/) installed on the target machine
you can easily install it in a terminal with,

    luarocks install lsqlite3

If the target server runs mods in secure mode[recommended], you must add sban
to the list of trusted mods in minetest.conf

#### COMMANDS

The mod provides the following chat console commands. These commands require
the ban privilege, ban_admin privilege increases the amount of information
displayed from the records.

#### ban

Bans a player permanently.

``` Usage: /ban <name_or_ip> <reason> ```

Example: /ban Steve Some reason.

Server privilege allows you to add bans for player names or ip's that the
server has no records for

#### tempban

Bans a player temporarily.

```Usage: /tempban <name_or_ip> <time> <reason>```

Just like xban2 the time parameter is a string in the format <count><unit>
where <unit> is one of s for seconds, m for minutes, h for hours, D for days,
W for weeks, M for months, or Y for years. If the unit is omitted, it is
assumed to mean seconds. For example, 42 means 42 seconds, 1337m 1337 minutes,
and so on. You can chain more than one such group and they will add up.
For example, 1Y3M3D7h will ban for 1 year, 3 months, 3 days and 7 hours.

Example: /tempban Steve 2D Some reason.

#### unban

Unbans a player.

```Usage: /unban <name_or_ip> <reason>```

Example: /unban Steve Some reason

#### ban_record

Shows the ban record on chat.

Usage: /ban_record <name_or_ip>

This prints player records and bans, with the time the ban came into effect,
the expiration time (if applicable), the reason, and the source of the ban.
The record is printed to chat with one entry per line. The records displayed
are limited by the conf setting sban.display_max to prevent spamming the chat
console, the default is last 10 records.

Example: /ban_record Steve

#### ban_wl

Manages the whitelist.

```Usage: /ban_wl (add|del|list) <name_or_ip>```

Whitelisted players are allowed on the server even if they are marked
as banned. This is useful to ensure moderators cannot ban each other,
for example.

The add subcommand adds the player to the whitelist.
The del subcommand removes the player from the whitelist.
The list subcommand lists the members on the whitelist.

Example: /ban_wl add Steve

#### ADMINISTRATION COMMANDS

These are commands for administering the server and require server privilege.
You can import current bans from the xban2 db file or ipban.txt

This is an intensive process that will lag the server so it's recommended
you perform the process on a local instance and copy the db to the server
before starting with sban mod installed.

#### ban_dbi

Imports bans from xban2 or ipban.

Usage: /ban_dbi <filename>

Example: /ban_dbi xban.db or /ban_dbi ipban.txt

It's also possible to put multiple files in the world folder and execute the
command on each file. For example:

    /ban_dbi xban_1.db
    /ban_dbi xban_2.db

each record is checked against the database, based on name to prevent duplicate
entries.

#### ban_dbe

Extracts all records from a xban2 file to sql inserts in a file you can
import via sqlite.

Usage: /ban_dbe <input_filename>

Example: /ban_dbe xban.db

This will create a file called sban.sql in the world folder, import the file
from sqlite prompt using:

    .open sban.sqlite
    .read sban.sql
    .exit

The time of the import operation is dependant on the size of the sql file.

#### CONFIG

You can add these optional settings to minetest.conf to alter some aspects of
sban mods behaviour.

sban.display_max

Changes the limit on the number of records displayed when using /ban_record
command.

sban.ban_max

This setting allows server owners to set an expiry date for bans. It uses the
same format as tempban for the time duration.

Example: sban.ban_max = 90D

In the example above all permanent player bans created after the setting has
been added to minetest.conf and a server restart, will expire 90 days after the
ban was set. Longer ban durations can easily be set with tempban if required,
after enabling. To return to normal behaviour delete the setting and restart
the server, bearing in mind existing bans created when it was active, will
still expire.

#### CREDITS:

Shara for suggesting improvements and providing a remote server test environment

