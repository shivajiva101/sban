# sban
[![Build status](https://github.com/shivajiva101/sban/workflows/Check%20&%20Release/badge.svg)](https://github.com/shivajiva101/sban/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This mod is based on the concepts introduced by xban2, and expands on them
by using an sql database instead of a serialised table file. This approach to
ban management:

* Offers API access to core functions that can be disabled if reqd
* Improves the robustness of the data.
* Grants an enhanced view of player accounts and ban records.
* Provides tiered access to player record information.
* Provides optional automatic ban expiration.
* Provides the capability to pre-emptively ban players.
* Offers increased accessibility via SSH connections to the database with your
favourite database management gui.
* Can preserve existing bans by importing records from Minetest or xban2.

Transactions are coded without locks so it's not recommended to write to
the database whilst Minetest is using it. Reading the database shouldn't be an issue.

<b>Existing users please note:</b> sban will not allow minetest to run if your db version doesn't match the current version required, if that happens and <b>only</b> if, you need to apply <b><i>sban/tools/sban_update.sql</b></i> to the database by copying the file into the world folder, then you can use sqlite3 in a terminal after navigating to the world folder using the commands:

	sqlite3 sban.sqlite
	.read sban_update.sql
	.exit

It's a good idea to make a backup prior to running the update just in case and the update should <b>not</b> be applied more than once!

#### INSTALLATION

sban requires lsqlite3 (https://github.com/LuaDist/lsqlite3).

If you have luarocks (https://luarocks.org/) installed on the target server,
you can easily install lsqlite3 in a terminal:

    sudo luarocks install lsqlite3

If the target server runs mods in secure mode[recommended], you must add sban
to the list of trusted mods in minetest.conf:

	secure.trusted_mods = sban

#### COMMANDS

The mod provides the following chat console commands. These commands require
the ban privilege. The ban_admin and server privileges extend the functionality
of some commands.

<b>bang</b>

Launches a GUI. Comprehensive management of bans via a user interface for in-game convenience.
On launch the interface shows a hotlist containing the last 10 players to join. Use search
to find a player if they are not currently in the list. Multiple records are shown if available,
accessible via the arrows.

``` Usage: /bang ```

<b>ban</b>

Bans a player permanently.

``` Usage: /ban <name_or_ip> <reason> ```

Example: /ban Steve Some reason.

The server privilege enables the pre-emptive banning of player names or
IP addresses for which the server has no current record.

<b>tempban</b>

Bans a player temporarily.

```Usage: /tempban <name_or_ip> <time> <reason>```

Example: /tempban Steve 2D Some reason.

The time parameter is a string in the format \<count> \<unit>,
where \<unit>  is either s for seconds, m for minutes, h for hours, D for days,
W for weeks, M for months, or Y for years. If the unit is omitted, it is
assumed to mean seconds. For example, 42 means 42 seconds, 1337m means 1337 minutes,
and so on. You can chain more than one such group and they will add up.
For example, 1Y3M3D7h will ban for 1 year, 3 months, 3 days and 7 hours.

<b>unban</b>

Unbans a player.

```Usage: /unban <name_or_ip> <reason>```

Example: /unban Steve Some reason.

Note that this command requires a reason.

<b>ban_record</b>

Displays player record and ban record.

```Usage: /ban_record <name_or_ip>```

Example: /ban_record Steve

This prints the player record and ban record for a player. The records are
printed to the chat console with one entry per line.

The player record includes names and, if sufficient privileges,
IP addresses used by the player. The number of records displayed is limited
to 10 by default to prevent chat console spam, and can be adjusted through
the setting sban.display_max in minetest.conf.

The ban record includes a list of all ban related actions performed on the player
under any known name or IP address. This includes the time a ban came into effect,
the expiration time (if applicable), the reason, and the source of the ban.

Note that the records of players with the server privilege can only be viewed
by other players with the server privilege.

<b>ban_wl</b>

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

This is an intensive process that will cause lag, so it's recommended
you perform this on a local instance and copy the database to the server
before starting with the sban mod installed.

<b>ban_dbi</b>

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

<b>ban_dbe</b>

Extracts all valid player records from an xban.db file and saves them in xban.sql.

```Usage: /ban_dbe <input_filename>```

Example: /ban_dbe xban.db

This creates a file called xban.sql in the world folder. Import the file
from the sqlite prompt using:

    .open sban.sqlite
    .read xban.sql
    .exit

The time of the import operation is dependant on the size of the .sql file.

<b>ban_dbx</b>

Dumps the database back to xban2 file format. Use it before you uninstall this mod
if you intend using xban2 and wish to retain the data.

```Usage: /ban_dbx```

Do this before enabling xban2 mod otherwise it will be overwritten by the currently loaded data.

<b>whois</b>

```Usage: //whois <name>```

Example: //whois sadie

Returns all known accounts and ip addresses associated with a player name.

#### CONFIG SETTINGS

You can add these optional settings to minetest.conf to adjust the sban mod's
behaviour. Deleting them removes the modification and sban will revert back to
the default behaviour. Minetest config file can only be changed when the server
isn't running!

<b>sban.api</b>

Controls loading of the API functions. <b>Default: true</b>

	sban.api = false

This would disable the API functions and prevent other mods access via the global sban table.

<b>sban.display_max</b>

Changes the maximum number of player records displayed when using the /ban_record
command.

	sban.display_max = 12

This would increase the number of records shown from the <b>default: 10</b> records to 12.

<b>sban.ban_max</b>

Allows server owners to set an expiry date for bans. It uses the same format for
durations as the /tempban command.

	sban.ban_max = 90D

In this example all permanent player bans created after the setting has been added
to minetest.conf, and after a server restart, will expire 90 days after the ban was
set. If required, longer ban durations can still be set with the tempban command.

<b>Please note:</b> existing ban expiry dates are not affected by changing this setting,
 including permanent bans but they will be applied to any subsequent new bans.

<b>sban.accounts_per_id</b>

Restricts how many accounts an id can have.

	sban.accounts_per_id = 5

Please note this setting is optional and the default behaviour is unrestricted.

<b>sban.ip_limit</b>

Restricts how many ip addresses an id can have.

	sban.ip_limit = 10
	
Please note this setting is optional and the default behaviour is unrestricted.

<b>sban.import_enabled</b>

Disables the import/export sections of code.

	sban.import_enabled = false

The default is true, this setting allows you to disable the code and commands associated with
importing & exporting data and should only be set to false once you have imported your ban sources.

<b>sban.cache.max</b>

Maximum cached name records.

	sban.cache.max = 1000

If you don't add this setting sban will use the value above as the default.

<b>sban.cache.ttl</b>

Time in seconds to deduct from the last player to login as the cutoff point for pre caching names.

	sban.cache.max = 86400

If you don't add this setting sban will use the value above as the default. Disable name caching by setting to -2


#### CREDITS

Thanks to:

Shara for suggesting improvements and editing documentation.    
rubenwardy for suggesting improvements to the interface layout.    
sofar for requesting a gui and suggesting the hotlist concept.    
