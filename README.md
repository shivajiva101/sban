# sban

This mod is based on the concepts introduced by xban2, and expands on them
by using an sql database instead of a serialised table file. This approach to
ban management:

* Improves the robustness of the data.
* Grants an enhanced view of player accounts and ban records.
* Provides tiered access to player record information.
* Provides automatic ban expiration.
* Provides the capability to pre-emptively ban players.
* Offers increased accessibility via SSH connections to the database with your
favourite database management gui.
* Can preserve existing bans by importing records from Minetest or xban2.

Currently the add and update transactions are coded without
locks so it's not recommended to write to the database whilst Minetest is using it.
Reading the database shouldn't be an issue.

#### INSTALLATION

sban requires lsqlite3 (https://github.com/LuaDist/lsqlite3).

If you have luarocks (https://luarocks.org/) installed on the target server,
you can easily install lsqlite3 in a terminal:

    luarocks install lsqlite3

If the target server runs mods in secure mode[recommended], you must add sban
to the list of trusted mods in minetest.conf:

	secure.trusted_mods = sban

#### COMMANDS

The mod provides the following chat console commands. These commands require
the ban privilege. The ban_admin and server privileges extend the functionality
of some commands.

#### bang

Launches the GUI. Comprehensive management of bans via a user interface for convenience.

``` Usage: /bang ```

#### ban

Bans a player permanently.

``` Usage: /ban <name_or_ip> <reason> ```

Example: /ban Steve Some reason.

The server privilege enables the pre-emptive banning of player names or
IP addresses for which the server has no current record.

#### tempban

Bans a player temporarily.

```Usage: /tempban <name_or_ip> <time> <reason>```

Example: /tempban Steve 2D Some reason.

The time parameter is a string in the format \<count> \<unit>,
where \<unit>  is either s for seconds, m for minutes, h for hours, D for days,
W for weeks, M for months, or Y for years. If the unit is omitted, it is
assumed to mean seconds. For example, 42 means 42 seconds, 1337m means 1337 minutes,
and so on. You can chain more than one such group and they will add up.
For example, 1Y3M3D7h will ban for 1 year, 3 months, 3 days and 7 hours.

#### unban

Unbans a player.

```Usage: /unban <name_or_ip> <reason>```

Example: /unban Steve Some reason.

Note that this command requires a reason.

#### ban_record

Displays player record and ban record.

```Usage: /ban_record <name_or_ip>```

Example: /ban_record Steve

This prints the player record and ban record for a player. The records are
printed to the chat console with one entry per line.

The player record includes names and, if the user has the ban_admin privilege,
IP addresses used by the player. The number of records displayed is limited
to 10 by default to prevent chat console spam, and can be adjusted through
the sban.display_max setting in minetest.conf.

The ban record includes a list of all ban related actions performed on the player
under any known name or IP address. This includes the time a ban came into effect,
the expiration time (if applicable), the reason, and the source of the ban.

Note that the records of players with the server privilege can only be viewed
by other players with the server privilege.

#### ban_wl

Manages the whitelist.

```Usage: /ban_wl (add|del|list) <name_or_ip>```

Example: /ban_wl add Steve

Whitelisted players are allowed on the server even if they are marked
as banned. This is useful to ensure moderators cannot ban each other.

The add subcommand adds a player to the whitelist.
The del subcommand removes a player from the whitelist.
The list subcommand lists the players on the whitelist.

#### ADMINISTRATION COMMANDS

These commands are for administering the server and require the server privilege.
You can import a server's previous ban history from xban2's xban.db file or from
Minetest's ipban.txt file.

This is an intensive process that will cause server lag, so it's recommended
you perform this on a local instance and copy the database to the server
before starting with the sban mod installed.

#### ban_dbi

Imports bans from xban.db or ipban.txt files into an existing
sban.sqlite file.

```Usage: /ban_dbi <filename>```

Example: /ban_dbi xban.db or /ban_dbi ipban.txt

It's possible to place multiple files in the world folder and execute the
command on each file. For example:

    /ban_dbi xban_1.db
    /ban_dbi xban_2.db

Each record is checked against the database by player name to prevent duplicate
entries.

#### ban_dbe

Extracts all valid player records from an xban.db file and saves them in xban.sql.

```Usage: /ban_dbe <input_filename>```

Example: /ban_dbe xban.db

This creates a file called xban.sql in the world folder. Import the file
from the sqlite prompt using:

    .open sban.sqlite
    .read xban.sql
    .exit

The time of the import operation is dependant on the size of the .sql file.

#### ban_dbx

Dumps the database to xban2 file format. 

```Usage: /ban_dbx```

Do this before enabling xban2 mod otherwise it will be overwritten by the currently loaded data.

#### CONFIG

You can add these optional settings to minetest.conf to adjust the sban mod's
behaviour.

#### sban.display_max

Changes the maximum number of player records displayed when using the /ban_record
command.

Example: sban.display_max = 12

This would increase the number of records shown from the default 10 records to 12.

#### sban.ban_max

Allows server owners to set an expiry date for bans. It uses the same format for
durations as the /tempban command.

Example: sban.ban_max = 90D

In this example all permanent player bans created after the setting has been added
to minetest.conf, and after a server restart, will expire 90 days after the ban was
set. If required, longer ban durations can still be set with the tempban command.

Please note that if you delete or adjust the setting, after restarting the server, bans
created while the setting was active will not change and will retain their adjusted
expiry dates.

#### CREDITS

Shara for suggesting improvements and providing a remote server test environment

