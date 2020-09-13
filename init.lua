--[[
sban mod for Minetest designed and coded by shivajiva101@hotmail.com

request an insecure enviroment to load the db handler
and access files in the world folder. This requires
access via secure.trusted in the minetest.conf file
before it will work! For example:

secure.trusted = sban

]]

local ie = minetest.request_insecure_environment()

-- success?
if not ie then
	error("insecure environment inaccessible" ..
	" - make sure this mod has been added to the" ..
	" secure.trusted setting in minetest.conf!")
end

local _sql = ie.require("lsqlite3")

-- secure this instance of sqlite3 global
if sqlite3 then sqlite3 = nil end

-- register privilege
minetest.register_privilege("ban_admin", {
	description = "ban administrator",
	give_to_singleplayer = false,
	give_to_admin = true,
})

local WP = minetest.get_worldpath()
local WL -- whitelist cache
local ESC = minetest.formspec_escape
local FORMNAME = "sban:main"
local bans = {}
local name_cache = {}
local ip_cache = {}
local hotlist = {}
local DB = WP.."/sban.sqlite"
local db_version = '0.2.1'
local db = _sql.open(DB) -- connection
local mod_version = '0.2.0'
local expiry, owner, owner_id, def_duration, display_max, names_per_id
local importer, ID, HL_Max, max_cache_records, ttl, cap, t_id, ip_limit
local formstate = {}
local t_units = {
	s = 1, S=1, m = 60, h = 3600, H = 3600,
	d = 86400, D = 86400, w = 604800, W = 604800,
	M = 2592000, y = 31104000, Y = 31104000, [""] = 1
}
local createDb, tmp_db, tmp_final
sban = {}

--[[
################
### Settings ###
################
]]

-- db
db:busy_timeout(50)

-- minetest.conf
if minetest.settings then
	expiry = minetest.settings:get("sban.ban_max")
	owner = minetest.settings:get("name")
	def_duration = minetest.settings:get("sban.fs_duration") or "1w"
	display_max = tonumber(minetest.settings:get("sban.display_max")) or 10
	names_per_id = tonumber(minetest.settings:get("sban.accounts_per_id"))
	ip_limit = tonumber(minetest.settings:get("sban.ip_limit"))
	importer = minetest.settings:get("sban.import_enabled") or true
	HL_Max = tonumber(minetest.settings:get("sban.hotlist_max")) or 15
	max_cache_records = tonumber(minetest.settings:get("sban.cache.max")) or 1000
	ttl = tonumber(minetest.settings:get("sban.cache.ttl")) or 86400
else
	-- old api method
	expiry = minetest.setting_get("sban.ban_max")
	owner = minetest.setting_get("name")
	def_duration = minetest.setting_get("sban.fs_duration") or "1w"
	display_max = tonumber(minetest.setting_get("sban.display_max")) or 10
	names_per_id = tonumber(minetest.setting_get("sban.accounts_per_id"))
	ip_limit = tonumber(minetest.setting_get("sban.ip_limit"))
	importer = minetest.setting_getbool("sban.import_enable") or true
	HL_Max = tonumber(minetest.setting_get("sban.hotlist_max")) or 15
	max_cache_records = tonumber(minetest.setting_get("sban.cache_max")) or 1000
	ttl = tonumber(minetest.setting_get("sban.cache_ttl")) or 86400
end

--[[
######################
###  DB callback  ###
######################
]]

-- debugging ONLY!!!
local dev = false
if dev then
	db:trace(
		function(ud, sql)
			minetest.log("action", "Sqlite Trace: " .. sql)
		end
	)

	-- Log the lines modified in the db
	optbl = {
		[_sql.UPDATE] = "UPDATE";
	    [_sql.INSERT] = "INSERT";
	    [_sql.DELETE] = "DELETE"
	 }
	setmetatable(optbl,
		{__index=function(t,n) return string.format("Unknown op %d",n) end})

	udtbl = {0, 0, 0}

	db:update_hook(
		function(ud, op, dname, tname, rowid)
			minetest.log("action", "[sban] " .. optbl[op] ..
			" applied to db table " .. tname .. " on rowid " .. rowid)
		end, udtbl
	)

end

--[[
###################
###  Functions  ###
###################
]]

-- Db wrapper for error reporting
-- @param stmt String containing SQL statements
-- @return error String or Boolean true
local function db_exec(stmt)
	if db:exec(stmt) ~= _sql.OK then
		minetest.log("error", "Sqlite ERROR:  "..db:errmsg())
		return db:errmsg()
	else
		return true
	end
end

-- Convert value to seconds (src: xban2)
-- @param t String containing alphanumerical duration
-- @return Integer seconds of duration
local function parse_time(str)
	local s = 0
	for n, u in str:gmatch("(%d+)([smhdwySHDWMY]?)") do
		s = s + (tonumber(n) * (t_units[u] or 1))
	end
	return s
end

-- Convert UTC to human readable date format
-- @param utc_int Integer, seconds since epoch
-- @return String containing datetime
local function hrdf(utc_int)
	if type(utc_int) == "number" then
		return (utc_int and os.date("%c", utc_int))
	end
end

-- Check if param is an ip address
-- @paran str String
-- @return true if ip else nil
local function is_ip(str)
	if str:find(":") or str:find("%.") then
		return true
	end
end

-- Escape special chars in reason string
-- @param str String input
-- @return escaped string
local function escape_string(str)
	local result
	result = str:gsub("'", "''")
	return result
end

-- format ip string
-- @param str String input
-- @return formatted String
local function ip_key(str)
	local result = str:gsub("%.", "")
	result:gsub('%:', '')
	return result
end

if importer then

createDb = [[
CREATE TABLE IF NOT EXISTS active (
	id INTEGER(10) PRIMARY KEY,
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS expired (
	id INTEGER(10),
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	u_source VARCHAR(50),
	u_reason VARCHAR(300),
	u_date INTEGER(30),
	last_pos VARCHAR(50)
);
CREATE INDEX IF NOT EXISTS idx_expired_id ON expired(id);

CREATE TABLE IF NOT EXISTS name (
	id INTEGER(10),
	name VARCHAR(50) PRIMARY KEY,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT(1)
);
CREATE INDEX IF NOT EXISTS idx_name_id ON name(id);
CREATE INDEX IF NOT EXISTS idx_name_lastlogin ON name(last_login);

CREATE TABLE IF NOT EXISTS address (
	id INTEGER(10),
	ip VARCHAR(50) PRIMARY KEY,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT(1),
	violation BOOLEAN
);
CREATE INDEX IF NOT EXISTS idx_address_id ON address(id);
CREATE INDEX IF NOT EXISTS idx_address_lastlogin ON address(last_login);

CREATE TABLE IF NOT EXISTS whitelist (
	name_or_ip VARCHAR(50) PRIMARY KEY,
	source VARCHAR(50),
	created INTEGER(30)
);

CREATE TABLE IF NOT EXISTS config (
	setting VARCHAR(28) PRIMARY KEY,
	data VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS violation (
	id INTEGER PRIMARY KEY,
	data VARCHAR
);

]]
db_exec(createDb)

tmp_db = [[
CREATE TABLE IF NOT EXISTS tmp_a (
	id INTEGER(10),
	name VARCHAR(50),
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT(1)
);

CREATE TABLE IF NOT EXISTS tmp_b (
	id INTEGER(10),
	ip VARCHAR(50),
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT(1),
	violation BOOLEAN
);

CREATE TABLE IF NOT EXISTS tmp_c (
	id INTEGER(10),
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS tmp_d (
	id INTEGER(10),
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	u_source VARCHAR(50),
	u_reason VARCHAR(300),
	u_date INTEGER(30),
	last_pos VARCHAR(50)
);

]]

tmp_final = [[

DELETE FROM tmp_a where rowid NOT IN (SELECT min(rowid) FROM tmp_a GROUP BY name);
DELETE FROM tmp_b where rowid NOT IN (SELECT min(rowid) FROM tmp_b GROUP BY ip);
DELETE FROM tmp_c where rowid NOT IN (SELECT min(rowid) FROM tmp_c GROUP BY id);

INSERT INTO name (id, name, created, last_login, login_count)
	SELECT * FROM tmp_a WHERE tmp_a.name NOT IN (SELECT name FROM name);

INSERT INTO address(id, ip, created, last_login, login_count, violation)
	SELECT * FROM tmp_b WHERE tmp_b.ip NOT IN (SELECT ip FROM address);

INSERT INTO active (id, name, source, created, reason, expires, pos)
	SELECT * FROM tmp_c WHERE tmp_c.id NOT IN (SELECT id FROM active);

INSERT INTO expired (id, name, source,created, reason, expires, u_source, u_reason, u_date, last_pos)
	SELECT * FROM tmp_d;

DROP TABLE tmp_a;
DROP TABLE tmp_b;
DROP TABLE tmp_c;
DROP TABLE tmp_d;

COMMIT;

PRAGMA foreign_keys = ON;

VACUUM;
]]
end

--[[
###########################
###  Database: Queries  ###
###########################
]]

-- Fetch an id for an ip or name
-- @param name_or_ip string
-- @returns id integer
local function get_id(name_or_ip)
	local q
	if is_ip(name_or_ip) then
		-- check cache first
		if ip_cache[ip_key(name_or_ip)] then
			return ip_cache[ip_key(name_or_ip)]
		end
		-- check db
		q = ([[
			SELECT id
			FROM address
			WHERE ip = '%s' LIMIT 1;]]
		):format(name_or_ip)
	else
		-- check cache first
		if name_cache[name_or_ip] then
			return name_cache[name_or_ip].id
		end
		-- check db
		q = ([[
			SELECT id
			FROM name
			WHERE name = '%s' LIMIT 1;]]
		):format(name_or_ip)
	end
	local it, state = db:nrows(q)
	local row = it(state)
	if row then
		return row.id
	end
end

-- Fetch last id from the name table
-- @return last id integer
local function last_id()
	local q = "SELECT MAX(id) AS id FROM name;"
	local it, state = db:nrows(q)
	local row = it(state)
	if row then
		return row.id
	end
end

-- Fetch expired ban records
-- @param id integer
-- @return ipair table of expired ban records
local function player_ban_expired(id)
	local r, q = {}
	q = ([[
	SELECT * FROM expired WHERE id = %i;
	]]):format(id)
	for row in db:nrows(q) do
		r[#r + 1] = row
	end
	return r
end

-- Fetch name records
-- @param id integer
-- @return ipair table of name records ordered by last login
local function name_records(id)
	local r, q = {}
	q = ([[
		SELECT * FROM name
		WHERE id = %i ORDER BY last_login DESC;
		]]):format(id)
	for row in db:nrows(q) do
		r[#r + 1] = row
	end
	return r
end

-- Fetch address records
-- @param id integer
-- @return ipair table of ip address records ordered by last login
local function address_records(id)
	local r, q = {}
	q = ([[
		SELECT * FROM address
		WHERE id = %i ORDER BY last_login DESC;
		]]):format(id)
	for row in db:nrows(q) do
		r[#r + 1] = row
	end
	return r
end

-- Fetch violation records
-- @param id integer
-- @return ipair table of violation records
local function violation_record(id)
	local q = ([[
		SELECT data FROM violation WHERE id = %i LIMIT 1;
	]]):format(id)
	local it, state = db:nrows(q)
	local row = it(state)
	if row then
		return minetest.deserialize(row.data)
	end
end

-- Fetch active bans
-- @return keypair table
local function get_active_bans()
	local r, q = {}
	q = "SELECT * FROM active;"
	for row in db:nrows(q) do
		r[row.id] = row
	end
	return r
end

-- Fetch whitelist
-- @return keypair table
local function get_whitelist()
	local r = {}
	local q = "SELECT * FROM whitelist;"
	for row in db:nrows(q) do
		r[row.name_or_ip] = true
	end
	return r
end

-- Fetch config setting
-- @param name setting string
-- @return data string
local function get_setting(name)
	local q = ([[SELECT data FROM config WHERE setting = '%s';]]):format(name)
	local it, state = db:nrows(q)
	local row = it(state)
	if row then
		return row.data
	end
end

-- Display player data on the console
-- @param caller name string
-- @param target name string
-- @return nil
local function display_record(caller, target)

	local id = get_id(target)
	local r = name_records(id)
	local bld = {}

	if not r then
		minetest.chat_send_player(caller, "No records for "..target)
		return
	end

	-- Show names
	local names = {}
	for i,v in ipairs(r) do
		table.insert(names, v.name)
	end
	bld[#bld+1] = minetest.colorize("#00FFFF", "[sban] records for: ") .. target
	bld[#bld+1] = minetest.colorize("#00FFFF", "Names: ") .. table.concat(names, ", ")

	local privs = minetest.get_player_privs(caller)

	-- records loaded, display
	local idx = 1
	if #r > display_max then
		idx = #r - display_max
		bld[#bld+1] = minetest.colorize("#00FFFF", "Name records: ")..#r..
		minetest.colorize("#00FFFF", " (showing last ")..display_max..
		minetest.colorize("#00FFFF", " records)")
	else
		bld[#bld+1] = minetest.colorize("#00FFFF", "Name records: ")..#r
	end
	for i = idx, #r do
		local d1 = hrdf(r[i].created)
		local d2 = hrdf(r[i].last_login)
		bld[#bld+1] = (minetest.colorize("#FFC000",
		"[%s]").." Name: %s Created: %s Last login: %s"):format(i, r[i].name, d1, d2)
	end

	if privs.ban_admin == true then
		r = address_records(id)
		if #r > display_max then
			idx = #r - display_max
			bld[#bld+1] = minetest.colorize("#0FF", "IP records: ") .. #r ..
			minetest.colorize("#0FF", " (showing last ") .. display_max ..
			minetest.colorize("#0FF", " records)")
		else
			bld[#bld+1] = minetest.colorize("#0FF", "IP records: ") .. #r
			idx = 1
		end
		for i = idx, #r do
			-- format utc values
			local d = hrdf(r[i].created)
			bld[#bld+1] = (minetest.colorize("#FFC000", "[%s] ")..
			"IP: %s Created: %s"):format(i, r[i].ip, d)
		end
		r = violation_record(id)
		if r then
			bld[#bld+1] = minetest.colorize("#0FF", "\nViolation records: ") .. #r
			for i,v in ipairs(r) do
				bld[#bld+1] = ("[%s] ID: %s IP: %s Created: %s Last login: %s"):format(
				i, v.id, v.ip, hrdf(v.created), hrdf(v.last_login))
			end
		else
			bld[#bld+1] = minetest.colorize("#0FF", "No violation records for ") .. target
		end
	end

	r = player_ban_expired(id) or {}
	bld[#bld+1] = minetest.colorize("#0FF", "Ban records:")
	if #r > 0 then

		bld[#bld+1] = minetest.colorize("#0FF", "Expired records: ")..#r

		for i, e in ipairs(r) do
			local d1 = hrdf(e.created)
			local expires = "never"
			if type(e.expires) == "number" and e.expires > 0 then
				expires = hrdf(e.expires)
			end
			local d2 = hrdf(e.u_date)
			bld[#bld+1] = (minetest.colorize("#FFC000", "[%s]")..
			" Name: %s Created: %s Banned by: %s Reason: %s Expires: %s "
		):format(i, e.name, d1, e.source, e.reason, expires) ..
			("Unbanned by: %s Reason: %s Time: %s"):format(e.u_source, e.u_reason, d2)
		end

	else
		bld[#bld+1] = "No expired ban records!"
	end

	r = bans[id]
	local ban = tostring(r ~= nil)
	bld[#bld+1] = minetest.colorize("#0FF", "Current Ban Status:")
	if ban == 'true' then
		local expires = "never"
		local d = hrdf(r.created)
		if type(r.expires) == "number" and r.expires > 0 then
			expires = hrdf(r.expires)
		end
		bld[#bld+1] = ("Name: %s Created: %s Banned by: %s Reason: %s Expires: %s"
		):format(r.name, d, r.source, r.reason, expires)
	else
		bld[#bld+1] = "no active ban record!"
	end
	bld[#bld+1] = minetest.colorize("#0FF", "Banned: ")..ban
	return table.concat(bld, "\n")
end

-- Fetch names like 'name'
-- @param name string
-- @return keypair table of names
local function get_names(name)
	local r,t,q = {},{}
	q = "SELECT name FROM name WHERE name LIKE '%"..name.."%';"
	for row in db:nrows(q) do
		-- Simple sort using a temp table to remove duplicates
		if not t[row.name] then
			r[#r+1] = row.name
			t[row.name] = true
		end
	end
	return r
end

cap = 0
-- Build name and address cache
-- @return nil
local function build_cache()
	-- get last login timestamp
	local q = "SELECT max(last_login) AS login FROM name;"
	local it, state = db:nrows(q)
	local last = it(state)
	if last.login then
		last = last.login - ttl -- adjust
		q = ([[
		SELECT * FROM name WHERE last_login > %i
		ORDER BY last_login ASC LIMIT %s;
		]]):format(last, max_cache_records)
		for row in db:nrows(q) do
			name_cache[row.name] = row
			cap = cap + 1
		end
		minetest.log("action", "[sban] caching " .. cap .. " name records")
		local ctr = 0
		for k, row in pairs(name_cache) do
			for _,v in ipairs(address_records(row.id)) do
				ip_cache[ip_key(v.ip)] = row.id
				ctr = ctr + 1
			end
		end
		minetest.log("action", "[sban] caching " .. ctr .. " ip records")
	end
end
build_cache()

-- Manage cache size
-- @return nil
local function trim_cache()
	if cap < max_cache_records then return end
	local entry = os.time()
	local name, id
	for key, data in pairs(name_cache) do
		if data.last_login < entry then
			entry = data.last_login
			name = key
			id = data.id
		end
	end
	for k,v in pairs(ip_cache) do
		if v == id then
			ip_cache[k] = nil
		end
	end
	name_cache[name] = nil
	cap = cap - 1
end

--[[
###########################
###  Database: Inserts  ###
###########################
]]

-- Create and cache name record
-- @param id integer
-- @param name string
-- @return nil
local function add_name(id, name)
	local ts = os.time()
	local stmt = ([[
			INSERT INTO name (id,name,created,last_login,login_count)
			VALUES (%i,'%s',%i,%i,1);
	]]):format(id, name, ts, ts)
	db_exec(stmt)
	-- cache name record
	name_cache[name] = {
		id = id,
		name = name,
		last_login = ts,
		login_count = 1
	}
end

-- Create and cache ip record
-- @param id integer
-- @param ip string
-- @return nil
local function add_ip(id, ip)
	local ts = os.time()
	local stmt = ([[
		INSERT INTO address (
			id,
			ip,
			created,
			last_login,
			login_count,
			violation
		) VALUES (%i,'%s',%i,%i,1,0);
	]]):format(id, ip, ts, ts)
	db_exec(stmt)
	-- cache
	ip_cache[ip_key(ip)] = id
end

-- Create and cache id record
-- @param name string
-- @param ip string
-- @return nil
local function create_player_record(name, ip)
	ID = ID + 1
	local ts = os.time()
	local stmt = ([[
		BEGIN TRANSACTION;
		INSERT INTO name (
			id,
			name,
			created,
			last_login,
			login_count
		) VALUES (%i,'%s',%i,%i,1);
		INSERT INTO address (
			id,
			ip,
			created,
			last_login,
			login_count,
			violation
		) VALUES (%i,'%s',%i,%i,1,0);
		COMMIT;
	]]):format(ID,name,ts,ts,ID,ip,ts,ts)
	db_exec(stmt)
	-- cache name record
	name_cache[name] = {
		id = ID,
		name = name,
		last_login = ts
	}
	return ID
end

-- Create ip violation record
-- @param src_id integer
-- @param target_id integer
-- @param ip string
-- @return nil
local function manage_idv_record(src_id, target_id, ip)
	local ts = os.time()
	local stmt
	local record = violation_record(src_id)
	if record then
		local idx
		for i,v in ipairs(record) do
			if v.id == target_id and v.ip == ip then
				idx = i
				break
			end
		end
		if idx then
			-- update record
			record[idx].ctr = record[idx].ctr + 1
			record[idx].last_login = ts
		else
			-- add record
			record[#record+1] = {
				id = target_id,
				ip = ip,
				ctr = 1,
				created = ts,
				last_login = ts
			}
		end
		stmt = ([[
			UPDATE violation SET data = '%s' WHERE id = %i;
		]]):format(minetest.serialize(record), src_id)
		db_exec(stmt)
	else
		record = {
			id = target_id,
			ip = ip,
			ctr = 1,
			created = ts,
			last_login = ts
		}
		stmt = ([[
			INSERT INTO violation VALUES (%i,'%s')
		]]):format(src_id, minetest.serialize(record))
		db_exec(stmt)
	end
end

-- Create whitelist record
-- @param source name string
-- @param name_or_ip string
-- @return nil
local function add_whitelist_record(source, name_or_ip)
	local ts = os.time()
	local stmt = ([[
			INSERT INTO whitelist
			VALUES ('%s', '%s', %i)
	]]):format(name_or_ip, source, ts)
	db_exec(stmt)
end

-- Create ban record
-- @param name string
-- @param source string
-- @param reason string
-- @param expires integer
-- @return nil
local function create_ban_record(name, source, reason, expires)

	local ts = os.time()
	local id = get_id(name)
	local player = minetest.get_player_by_name(name)
	local p_reason = escape_string(reason)

	expires = expires or 0

	-- initialise last position
	local last_pos = ""
	if player then
		last_pos = minetest.pos_to_string(vector.round(player:getpos()))
	end

	-- cache the ban
	bans[id] = {
		id = id,
		name = name,
		source = source,
		created = ts,
		reason = reason,
		expires = expires,
		last_pos = last_pos
	}

	-- add record
	local stmt = ([[
		INSERT INTO active VALUES (%i,'%s','%s',%i,'%s',%i,'%s');
	]]):format(id, name, source, ts, p_reason, expires, last_pos)
	db_exec(stmt)

	-- owner cannot be kicked!
	if not dev and owner_id == id then return end

	-- create kick & log messages
	local msg_k, msg_l
	if expires ~= 0 then
		local date = hrdf(expires)
		msg_k = ("Banned: Expires: %s, Reason: %s"
		):format(date, reason)
		msg_l = ("[sban] %s temp banned by %s reason: %s"
		):format(name, source, reason)
	else
		msg_k = ("Banned: Reason: %s"):format(reason)
		msg_l = ("[sban] %s banned by %s reason: %s"
		):format(name, source, reason)
	end
	minetest.log("action", msg_l)

	-- kick all player names associated with the id
	local r = name_records(id)
	if #r < 1 then -- sanity check for timeout
		r[1] = {name = name}
		minetest.log('warning', db:errmsg())
	end
	for i, v in ipairs(r) do
		player = minetest.get_player_by_name(v.name)
		if player then
			-- defeat entity attached bypass mechanism
			player:set_detach()
			minetest.kick_player(v.name, msg_k)
		end
	end
end

-- initialise db version
-- @param str version string
-- @return nil
local function init_setting(setting, data)
	local stmt = ([[
		INSERT INTO config VALUES ('%s', '%s');
	]]):format(setting, data)
	db_exec(stmt)
end

--[[
###########################
###  Database: Updates  ###
###########################
]]

-- Update login record
-- @param id integer
-- @param name string
-- @return nil
local function update_login(id, name)
	local ts = os.time()
	-- cache handler
	if not name_cache[name] then
		name_cache[name] = {
			id = id,
			name = name,
			last_login = ts
		}
	else
		name_cache[name].last_login = ts
	end
	-- update Db name record
	local stmt = ([[
	UPDATE name SET
	last_login = %i,
	login_count = login_count + 1
	WHERE name = '%s';
	]]):format(ts, name)
	db_exec(stmt)
end

-- Update address record
-- @param id integer
-- @param ip string
-- @return nil
local function update_address(id, ip)
	local ts = os.time()
	local stmt = ([[
	UPDATE address
	SET
	last_login = %i,
	login_count = login_count + 1
	WHERE id = %i AND ip = '%s';
	]]):format(ts, id, ip)
	db_exec(stmt)
end

-- Update ban record
-- @param id integer
-- @param source name string
-- @param reason string
-- @param name string
-- @return nil
local function update_ban_record(id, source, reason, name)
	reason = escape_string(reason)
	local ts = os.time()
	local row = bans[id] -- use cached data
	local stmt = ([[
		INSERT INTO expired VALUES (%i,'%s','%s',%i,'%s',%i,'%s','%s',%i,'%s');
		DELETE FROM active WHERE id = %i;
	]]):format(row.id, row.name, row.source, row.created, escape_string(row.reason),
	row.expires, source, reason, ts, row.pos, row.id)
	db_exec(stmt)
	bans[id] = nil -- update cache
	-- log event
	minetest.log("action",
	("[sban] %s unbanned by %s reason: %s"):format(name, source, reason))
end

-- Update violation status
-- @param ip string
-- @return nil
local function update_idv_status(ip)
	local stmt = ([[
	UPDATE address
	SET
	violation = 'true'
	WHERE ip = '%s';
	]]):format(ip)
	db_exec(stmt)
end

--[[
##################################
###  Database: Delete Records  ###
##################################
]]

-- Remove ban recors
-- @param id integer
-- @return nil
local function del_ban_record(id)
	local stmt = ([[
		DELETE FROM active WHERE id = %i
	]]):format(id)
	db_exec(stmt)
	bans[id] = nil -- update cache
end

-- Remove whitelist entry
-- @param name_or_ip string
-- @return nil
local function del_whitelist(name_or_ip)
	local stmt = ([[
		DELETE FROM whitelist WHERE name_or_ip = '%s'
	]]):format(name_or_ip)
	db_exec(stmt)
end

--[[
#######################
###  Export/Import  ###
#######################
]]

if importer then -- always true for first run

	-- Load and deserialise xban2 file
	-- @param filename string
	-- @return table
	local function load_xban(filename)
		local f, e = ie.io.open(WP.."/"..filename, "rt")
		if not f then
			return false, "Unable to load xban2 database:" .. e
		end
		local content = f:read("*a")
		f:close()
		if not content then
			return false, "Unable to load xban2 database: Read failed!"
		end
		local t = minetest.deserialize(content)
		if not t then
			return false, "xban2 database: Deserialization failed!"
		end
		return t
	end

	-- Load ipban file
	-- @return string
	local function load_ipban()
		local f, e = ie.io.open(WP.."/ipban.txt")
		if not f then
			return false, "Unable to open 'ipban.txt': "..e
		end
		local content = f:read("*a")
		f:close()
		return content
	end

	-- Write sql file
	-- @param string containing fle contents
	-- @return nil
	local function save_sql(txt)
		local file = ie.io.open(WP.."/xban.sql", "a")
		if file and txt then
			file:write(txt)
			file:close()
		end
	end

	-- Delete sql file
	-- @return nil
	local function del_sql()
		ie.os.remove(WP.."/xban.sql")
	end

	-- Create SQL string
	-- @param id integer
	-- @param entry keypair table
	-- @return formatted string
	local function sql_string(id, entry)
		local names = {}
		local ip = {}
		local last_seen = entry.last_seen or 0
		local last_pos = entry.last_pos or ""

		-- names field includes both IP and names data, sort into 2 tables
		for k, v in pairs(entry.names) do
			if is_ip(k) then
				table.insert(ip, k)
			else
				table.insert(names, k)
			end
		end

		local q = ""

		for i, v in ipairs(names) do
			q = q..("INSERT INTO tmp_a VALUES (%i,'%s',%i,%i, 0);\n"
			):format(id, v, last_seen, last_seen)
		end
		for i, v in ipairs(ip) do
			-- address fields: id,ip,created,last_login,login_count,violation
			q = q..("INSERT INTO tmp_b VALUES (%i,'%s',%i,%i,1,0);\n"
			):format(id, v, last_seen, last_seen)
		end

		if #entry.record > 0 then

			local ts = os.time()
			-- bans to archive
			for i, v in ipairs(entry.record) do

				local expires = v.expires or 0
				local reason = string.gsub(v.reason, "'", "''")

				reason = string.gsub(reason, "%:%)", "") -- remove colons

				if last_pos.y then
					last_pos = vector.round(last_pos)
					last_pos = minetest.pos_to_string(last_pos)
				end

				if entry.reason and entry.reason == v.reason then
					-- active ban
					-- fields: id,name,source,created,reason,expires,last_pos
					q = q..("INSERT INTO tmp_c VALUES (%i,'%s','%s',%i,'%s',%i,'%s');\n"
					):format(id, names[1], v.source, v.time, reason, expires, last_pos)
				else
					-- expired ban
					-- fields: id,name,source,created,reason,expires,u_source,u_reason,
					-- u_date,last_pos
					q = q..("INSERT INTO tmp_d VALUES (%i,'%s','%s',%i,'%s',%i,'%s','%s',%i,'%s');\n"
					):format(id, names[1], v.source, v.time, reason, expires, 'sban',
					'expired prior to import', ts, last_pos)
				end
			end
		end

		return q
	end

	-- Import xban2 file active ban records
	-- @param file_name string
	-- @return nil
	local function import_xban(file_name)

		local t, err = load_xban(file_name)

		if not t then -- exit with error message
			return false, err
		end

		local id = ID
		local bl = {}
		local tl = {}

		minetest.log("action", "processing "..#t.." records")

		for i, v in ipairs(t) do
			if v.banned == true then
				bl[#bl+1] = v
				t[i] = nil
			end
		end

		minetest.log("action", "found "..#bl.." active ban records")

		tl[#tl+1] = "PRAGMA foreign_keys = OFF;\n"
		tl[#tl+1] = tmp_db
		tl[#tl+1] = "BEGIN TRANSACTION;"

		for i = #bl, 1, -1 do
			if bl[i] then
				id = id + 1
				tl[#tl+1] = sql_string(id, bl[i])
				bl[i] = nil -- shrink
			end
		end

		tl[#tl+1] = tmp_final
		-- run the prepared statement
		db_exec(table.concat(tl, "\n"))
		ID = id -- update global
		return true
	end

	-- Import ipban file records
	-- @param file_name string
	-- @return nil
	local function import_ipban(file_name)
		local contents = load_ipban()
		if not contents then
			return false
		end
		local data = string.split(contents, "\n")
		for i, v in ipairs(data) do
			-- each line consists of an ip, separator and name
			local ip, name = v:match("([^|]+)%|(.+)")
			if ip and name then
				-- check for an existing entry by name
				local id = get_id(name)
				if not id then
					id = create_player_record(name, ip)
				end
				-- check for existing ban
				if not bans[id] then
					-- create ban entry - name,source,reason,expires
					create_ban_record(name, 'sban', 'imported from ipban.txt', '')
				end
			end
		end
	end

	-- Export xban2 file to SQL file
	-- @param filename string
	-- @return nil
	local function export_sql(filename)
		-- load the db, iterate in reverse order and remove each
		-- record to balance the memory use otherwise large files
		-- cause lua OOM error
		local dbi, err = load_xban(filename)
		local id = ID
		if err then
			minetest.log("warning", err)
			return
		end
		-- reverse the contents
		for i = 1, math.floor(#dbi / 2) do
			local tmp = dbi[i]
			dbi[i] = dbi[#dbi - i + 1]
			dbi[#dbi - i + 1] = tmp
		end

		save_sql("PRAGMA foreign_keys = OFF;\n\n")
		save_sql(createDb)
		save_sql(tmp_db)
		save_sql("BEGIN TRANSACTION;\n\n")
		-- process records
		for i = #dbi, 1, - 1 do
			-- contains data?
			if dbi[i] then
				id = id + 1
				local str = sql_string(id, dbi[i]) -- sql statement
				save_sql(str)
				dbi[i] = nil -- shrink
			end
		end
		-- add sql inserts to transfer the data, clean up and finalise
		save_sql(tmp_final)
	end

	-- Export db bans to xban2 file format
	-- @return nil
	local function export_to_xban()
		local xport = {}
		local DEF_DB_FILENAME = minetest.get_worldpath().."/xban.db"
		local DB_FILENAME = minetest.setting_get("xban.db_filename")

		if (not DB_FILENAME) or (DB_FILENAME == "") then
			DB_FILENAME = DEF_DB_FILENAME
		end

		-- initialise table of banned id's
		for k,v in pairs(bans) do
			local id = v.id
			xport[id] = {
				banned = true,
				names = {}
			}
			local t = {}
			local q = ([[SELECT * FROM name
			WHERE id = %i]]):format(id)
			for row in db:nrows(q) do
				xport[id].names[row.name] = true
			end
			q = ([[SELECT * FROM address
			WHERE id = %i]]):format(id)
			for row in db:nrows(q) do
				xport[id].names[row.ip] = true
			end
			q = ([[SELECT * FROM expired WHERE id = %i;]]):format(id)
			for row in db:nrows(q) do
				t[#t+1] = {
					time = row.created,
					source = row.source,
					reason = row.reason
				}
			end
			t[#t+1] = {
				time = bans[id].created,
				source = bans[id].source,
				reason = bans[id].reason
			}
			xport[id].record = t
			xport[id].last_seen = bans[id].last_login
			xport[id].last_pos = bans[id].last_pos or ""
		end

		local function repr(x)
			if type(x) == "string" then
				return ("%q"):format(x)
			else
				return tostring(x)
			end
		end

		local function my_serialize_2(t, level)
			level = level or 0
			local lines = { }
			local indent = ("\t"):rep(level)
			for k, v in pairs(t) do
				local typ = type(v)
				if typ == "table" then
					table.insert(lines,
					  indent..("[%s] = {\n"):format(repr(k))
					  ..my_serialize_2(v, level + 1).."\n"
					  ..indent.."},")
				else
					table.insert(lines,
					  indent..("[%s] = %s,"):format(repr(k), repr(v)))
				end
			end
			return table.concat(lines, "\n")
		end

		local function this_serialize(t)
			return "return {\n"..my_serialize_2(t, 1).."\n}"
		end

		local f, e = io.open(DB_FILENAME, "wt")
		xport.timestamp = os.time()
		if f then
			local ok, err = f:write(this_serialize(xport))
			if not ok then
				minetest.log("error", "Unable to save database: %s", err)
			end
		else
			minetest.log("error", "Unable to save database: %s", e)
		end
		if f then f:close() end
	end

	-- Register export to SQL file command
	minetest.register_chatcommand("ban_dbe", {
		description = "export xban2 db to sql format",
		params = "<filename>",
		privs = {server = true},
		func = function(name, params)
			local filename = params:match("%S+")
			if not filename then
				return false, "Use: /ban_dbe <filename>"
			end
			del_sql()
			export_sql(filename)
			return true, filename .. " dumped to xban.sql"
		end
	})

	-- Register export to xban2 file format
	minetest.register_chatcommand("ban_dbx", {
		description = "export db to xban2 format",
		privs = {server = true},
		func = function(name)
			export_to_xban()
			return true, "dumped db to xban2 file!"
		end
	})

	-- Register ban import command
	minetest.register_chatcommand("ban_dbi", {
		description = "Import bans",
		params = "<filename>",
		privs = {server = true},
		func = function(name, params)
			local filename = params:match("%S+")
			if not filename then
				return false, "Use: /ban_dbi <filename>"
			end
			local msg
			if filename == "ipban.txt" then
				import_ipban(name)
				msg = "ipban.txt imported!"
			else
				local res, err = import_xban(filename)
				msg = err
				if res then
					msg = filename.." bans imported!"
				end
			end
			return true, msg
		end
	})
end

--[[
##############
###  Misc  ###
##############
]]

-- initialise config
local current_version = get_setting("db_version")
if not current_version then -- first run
	init_setting('db_version', db_version)
	init_setting('mod_version', mod_version)
elseif not current_version == db_version then
	error("You must update sban database to "..db_version..
	"\nUse sqlite3 to import /tools/sban_update.sql")
end

-- initialise caches
WL = get_whitelist()
bans = get_active_bans()
ID = last_id() or 0
owner_id = get_id(owner)
t_id = {}

-- Add an entry to and manage size of hotlist
-- @param name string
-- @return nil
local function manage_hotlist(name)
	for _, v in ipairs(hotlist) do
		if v == name then
			-- no duplicates
			return
		end
	end
	-- fifo
	table.insert(hotlist, name)
	if #hotlist > HL_Max then
		table.remove(hotlist, 1)
	end
end

-- Manage expired bans
-- @return nil
local function process_expired_bans()
	local ts = os.time()
	local tq = {}
	for id_key,row in pairs(bans) do
		if type(row.expires) == "number" and row.expires ~= 0 then
			-- temp ban
			if ts > row.expires then
				row.last_pos = row.last_pos or "" -- can't be nil!
				-- add sql statements
				tq[#tq+1] = ([[
					INSERT INTO expired VALUES (%i,'%s','%s',%i,'%s',%i,'sban','tempban expired',%i,'%s');
					DELETE FROM active WHERE id = %i;
				]]):format(row.id, row.name, row.source, row.created, escape_string(row.reason),
				row.expires, ts, row.last_pos, row.id)
			end
		end
	end
	if #tq > 0 then
		-- finalise & execute
		tq[#tq+1] = "VACUM;"
		db_exec(table.concat(tq, "\n"))
	end
end
process_expired_bans() -- trigger on mod load

local function clean_join_cache(name)
	local ts = os.time()
	local TTL = 10 -- ttl in seconds
	for k,v in pairs(t_id) do
		if (v.ts + TTL) < ts or k == name then
			t_id[k] = nil
		end
	end
end

-- fix irc mod with an override
if irc then -- luacheck: ignore
    irc.reply = function(message) -- luacheck: ignore
        if not irc.last_from then -- luacheck: ignore
            return
        end
        message = message:gsub("[\r\n%z]", " \\n ")
        local helper = string.split(message, "\\n")
        for i,v in ipairs(helper) do
            irc.say(irc.last_from, minetest.strip_colors(v)) -- luacheck: ignore
        end
    end
end

--[[
###########
##  GUI  ##
###########
]]

-- Fetch and format ban info
-- @param entry keypair table
-- @return formatted string
local function create_info(entry)
	-- returns an info string, line wrapped based on the ban record
	if not entry then
		return "something went wrong!\n Please reselect the entry."
	end
	local str = "Banned by: "..entry.source.."\n"
		.."When: "..hrdf(entry.created).."\n"
	if entry.expires ~= 0 then
		str = str.."Expires: "..hrdf(entry.expires).."\n"
	end
	str = str .."Reason: "
	-- Word wrap
	local words = entry.reason:split(" ")
	local l,ctr = 40,8 -- initialise limits
	for _,word in ipairs(words) do
		local wl = word:len()
		if ctr + wl < l then
			str = str..word.." "
			ctr = ctr + (wl + 1)
		else
			str = str.."\n"..word.." "
			ctr = wl + 1
		end
	end
	return str
end

-- Fetch formstate, initialising if reqd
-- @param name string
-- @return keypair state table
local function get_state(name)
	local s = formstate[name]
	if not s then
		s = {
			list = {},
			hlist = {},
			index = -1,
			info = "Select an entry from the list\n or use search",
			banned = false,
			ban = nil,
			multi = false,
			page = 1,
			flag = false
		}
		formstate[name] = s
	end
	return s
end

-- Update state table
-- @param name string
-- @param selected string
-- @return nil
local function update_state(name, selected)
	-- updates state used by formspec
	local fs = get_state(name)
	local id = get_id(selected)

	fs.ban = player_ban_expired(id)
	local cur = bans[id]
	if cur then table.insert(fs.ban, cur) end

	local info = "Ban records: "..#fs.ban.."\n"

	fs.banned = cur
	fs.multi = false

	if #fs.ban == 0 then
		info = info.."Player has no ban records!"
	else
		if not fs.flag then
			fs.page = #fs.ban
			fs.flag = true
		end
		if fs.page > #fs.ban then fs.page = #fs.ban end
		info = info..create_info(fs.ban[fs.page])
	end

	fs.info = info
	if #fs.ban > 1 then
		fs.multi = true
	end
end

-- Fetch user formspec
-- @param name string
-- @return formspec string
local function getformspec(name)

	local fs = formstate[name]
	local f
	local list = fs.list
	local bgimg = ""
	if default and default.gui_bg_img then
		bgimg = default.gui_bg_img
	end

	f = {}
	f[#f+1] = "size[8,6.6]"
	f[#f+1] = bgimg
	f[#f+1] = "field[0.3,0.4;4.5,0.5;search;;]"
	f[#f+1] = "field_close_on_enter[search;false]"
	f[#f+1] = "button[4.5,0.1;1.5,0.5;find;Find]"
	if #fs.list > 0 then
		f[#f+1] = "textlist[0,0.9;2.4,3.6;plist;"
		local tmp = {}
		for i,v in ipairs(list) do
			tmp[#tmp+1] = v
		end
		f[#f+1] = table.concat(tmp, ",")
		f[#f+1] = ";"
		f[#f+1] = fs.index
		f[#f+1] = "]"
	end
	f[#f+1] = "field[0.3,6.5;4.5,0.5;reason;Reason:;]"
	f[#f+1] = "field_close_on_enter[reason;false]"

	if fs.multi == true then
		f[#f+1] = "image_button[6,0.1;0.5,0.5;ui_left_icon.png;left;]"
		f[#f+1] = "image_button[7,0.1;0.5,0.5;ui_right_icon.png;right;]"
		if fs.page > 9 then
			f[#f+1] = "label[6.50,0.09;"
			f[#f+1] = fs.page
			f[#f+1] = "]"
		else
			f[#f+1] = "label[6.55,0.09;"
			f[#f+1] = fs.page
			f[#f+1] = "]"
		end
	end

	f[#f+1] = "label[2.6,0.9;"
	f[#f+1] = fs.info
	f[#f+1] = "]"

	if fs.banned then
		f[#f+1] = "button[4.5,6.2;1.5,0.5;unban;Unban]"
	else
		f[#f+1] = "field[0.3,5.5;2.6,0.3;duration;Duration:;"
		f[#f+1] = def_duration
		f[#f+1] = "]"
		f[#f+1] = "field_close_on_enter[duration;false]"
		f[#f+1] = "button[4.5,6.2;1.5,0.5;ban;Ban]"
		f[#f+1] = "button[6,6.2;2,0.5;tban;Temp Ban]"
	end

	return table.concat(f)
end

-- Register form submission callbacks
minetest.register_on_player_receive_fields(function(player, formname, fields)

	if formname ~= FORMNAME then return end

	local name = player:get_player_name()
	local privs = minetest.get_player_privs(name)
	local fs = get_state(name)

	if not privs.ban then
		minetest.log(
		"warning", "[sban] Received fields from unauthorized user: "..name)
		create_ban_record(name, 'sban', 'detected using a hacked client!')
		return
	end

	if fields.find then

		if fields.search:len() > 2 then
			fs.list = get_names(ESC(fields.search))
		else
			fs.list = fs.hlist
		end
		local str = "No record found!"
		if #fs.list > 0 then
			str = "Select an entry to see the details..."
		end
		fs.info = str
		fs.index = -1
		minetest.show_formspec(name, FORMNAME, getformspec(name))

	elseif fields.plist then

		local t = minetest.explode_textlist_event(fields.plist)

		if (t.type == "CHG") or (t.type == "DCL") then

			fs.index = t.index
			fs.flag = false -- reset
			update_state(name, fs.list[t.index])
			minetest.show_formspec(name, FORMNAME, getformspec(name))
		end

	elseif fields.left or fields.right then

		if fields.left then
			if fs.page > 1 then fs.page = fs.page - 1 end
		else
			if fs.page < #fs.ban then fs.page = fs.page + 1 end
		end
		update_state(name, fs.list[fs.index])
		minetest.show_formspec(name, FORMNAME, getformspec(name))

	elseif fields.ban or fields.unban or fields.tban then

		local selected = fs.list[fs.index]
		local id = get_id(selected)

		if fields.reason ~= "" then
			if fields.ban then
				if selected == owner then
					fs.info = "you do not have permission to do that!"
				else
					create_ban_record(selected, name, ESC(fields.reason), 0)
				end
			elseif fields.unban then
				update_ban_record(id, name, ESC(fields.reason), selected)
				fs.ban = player_ban_expired(id)
			elseif fields.tban then
				if selected == owner then
					fs.info = "you do not have permission to do that!"
				else
					local  t = parse_time(ESC(fields.duration)) + os.time()
					create_ban_record(selected, name, ESC(fields.reason), t)
				end
			end
			fs.flag = false -- reset
			update_state(name, selected)
		else
			fs.info = "You must supply a reason!"
		end
		minetest.show_formspec(name, FORMNAME, getformspec(name))
	end
end)

--[[
###########################
###  Register Commands  ###
###########################
]]

-- Register ban command
minetest.override_chatcommand("ban", {
	description = "Bans a player from the server",
	params = "<player> <reason>",
	privs = { ban = true },
	func = function(name, params)
		local player_name, reason = params:match("(%S+)%s+(.+)")

		if not (player_name and reason) then
			-- check params are present
			return false, "Usage: /ban <player> <reason>"
		end

		if player_name == owner then
			-- protect owner
			return false, "Insufficient privileges!"
		end

		local expires = 0
		local id = get_id(player_name)

		if id then
			-- check for existing ban
		   if bans[id] then
			   return true, ("%s is already banned!"):format(player_name)
		   end
			-- limit ban?
			if expiry then
				expires = parse_time(expiry) + os.time()
			end
			-- Params: name, source, reason, expires
			create_ban_record(player_name, name, reason, expires)
		else
			local privs = minetest.get_player_privs(name)
			-- ban_admin only
			if not privs.ban_admin then
				return false, "Player "..player_name.." doesn't exist!"
			end
			-- create entry & ban
			ID = ID + 1 -- increment last id
			add_name(ID, player_name)
			create_ban_record(player_name, name, reason, expires)
		end
		return true, ("Banned %s."):format(player_name)
	end
})

-- Register ban deletion command
minetest.register_chatcommand("ban_del", {
	description = "Deletes a player's sban records",
	params = "player",
	privs = {server = true},
	func = function(name, params)
		local player_name = params:match("%S+")
		if not player_name then
			return false, "Usage: /ban_del_record <player>"
		end
		local id = get_id(player_name)
		if not id then
			return false, player_name.." doesn't exist!"
		end
		del_ban_record(id)
		minetest.log("action",
		"ban records for "..player_name.." deleted by "..name)
		return true, player_name.." ban records deleted!"
	end
})

-- Register info command
minetest.register_chatcommand("ban_record", {
	description = "Display player sban records",
	params = "<player_or_ip>",
	privs = { ban = true },
	func = function(name, params)
		local playername = params:match("%S+")
		if not playername or playername:find("*") then
			return false, "usage: /ban_record <player_name>"
		end
		-- get target and source privs
		local id = get_id(playername)
		if not id then
			return false, "Unknown player!"
		end
		local target = name_records(id)
		local source = minetest.get_player_privs(name)
		local chk = false
		for i, v in ipairs(target) do
			local privs = minetest.get_player_privs(v.name)
			if privs.server then chk = true break end
		end
		-- if source doesn't have sufficient privs deny & inform
		if not source.server and chk then
			return false, "Insufficient privileges to access that information"
		end
		return true, display_record(name, playername)
	end
})

-- Register whitelist command
minetest.register_chatcommand("ban_wl", {
	description = "Manages the whitelist",
	params = "(add|del|list) <name_or_ip>",
	privs = {server = true},
	func = function(name, params)
		local helper = ("Usage: /ban_wl (add|del) "
		.."<name_or_ip> \nor /ban_wl list")
		local param = {}
		local i = 1
		for word in params:gmatch("%S+") do
			param[i] = word
			i = i + 1
		end
		if #param < 1 then
			return false, helper
		end
		if param[1] == "list" then
			local str = ""
			for k, v in pairs(WL) do
				str = str..k.."\n"
			end
			if str ~= "" then
				return true, str
			end
			return true, "Whitelist empty!"
		end
		if param[2] then
			if param[1] == "add" then
				if not WL[param[2]] then
					add_whitelist_record(name, param[2])
					WL[param[2]] = true
					minetest.log("action",
					("%s added %s to whitelist"):format(name, param[2]))
					return true, param[2].." added to whitelist!"
				else
					return false, param[2].." is already whitelisted!"
				end
			elseif param[1] == "del" then
				if WL[param[2]] then
					del_whitelist(param[2])
					WL[param[2]] = nil
					minetest.log("action", ("%s removed %s from whitelist"
					):format(name, param[2]))
					return true, param[2].." removed from whitelist!"
				else
					return false, param[2].." isn't on the whitelist"
				end
			end
		end
		return false, helper
	end
})

-- Register temp ban command
minetest.register_chatcommand("tempban", {
	description = "Ban a player temporarily with sban",
	params = "<player> <time> <reason>",
	privs = { ban = true },
	func = function(name, params)
		local player_name, time, reason = params:match("(%S+)%s+(%S+)%s+(.+)")

		if not (player_name and time and reason) then
			-- correct params?
			return false, "Usage: /tempban <player> <time> <reason>"
		end

		if player_name == owner then
			-- protect owner account
			return false, "Insufficient privileges!"
		end

		time = parse_time(time)
		if time < 60 then
			return false, "You must ban for at least 60 seconds."
		end
		local expires = os.time() + time

		-- is player already banned?
		local id = get_id(player_name)
		if id then
			if bans[id] then
				return true, ("%s is already banned!"):format(player_name)
			end
			create_ban_record(player_name, name, reason, expires)
		else
			local privs = minetest.get_player_privs(name)
			-- assert normal behaviour without server priv
			if not privs.ban_admin then
				return false, "Player doesn't exist!"
			end
			-- create entry before ban
			ID = ID + 1
			add_name(ID, player_name)
			create_ban_record(player_name, name, reason, expires)
		end
			return true, ("Banned %s until %s."):format(
			player_name, os.date("%c", expires))
	end,
})

-- Register unban command
minetest.override_chatcommand("unban", {
	description = "Unban a player or ip banned with sban",
	params = "<player_or_ip> <reason>",
	privs = { ban = true },
	func = function(name, params)
		local player_name, reason = params:match("(%S+)%s+(.+)")
		if not (player_name and reason) then
		return false, "Usage: /unban <player_or_ip> <reason>"
		end
		-- look for records by id
		local id = get_id(player_name)
		if id then
			if not bans[id] then
				return false, ("No active ban record for "..player_name)
			end
			update_ban_record(id, name, reason, player_name)
			return true, ("Unbanned %s."):format(player_name)
		end
	end,
})

-- Register GUI command
minetest.register_chatcommand("bang", {
	description = "Launch sban gui",
	privs = {ban = true},
	func = function(name)
		formstate[name] = nil
		local fs = get_state(name)
		fs.list = hotlist
		for i,v in ipairs(fs.list) do
			fs.hlist[i] = v
		end
		minetest.show_formspec(name, FORMNAME, getformspec(name))
	end
})

-- Register kick command (reqd for 5.0 ?)
minetest.override_chatcommand("kick", {
	params = "<name> [reason]",
	description = "Kick a player",
	privs = {kick=true},
	func = function(name, param)
		local tokick, reason = param:match("([^ ]+) (.+)")
		tokick = tokick or param
		local player = minetest.get_player_by_name(tokick)
		if not player then
			return false, "Player " .. tokick .. " not in game!"
		end
		if not minetest.kick_player(tokick, reason) then
			player:set_detach()
			if not minetest.kick_player(tokick, reason) then
				return false, "Failed to kick player " .. tokick ..
				" after detaching!"
			end
		end
		local log_reason = ""
		if reason then
			log_reason = " with reason \"" .. reason .. "\""
		end
		minetest.log("action", name .. " kicks " .. tokick .. log_reason)
		return true, "Kicked " .. tokick
  end,
})

-- Register whois command
minetest.register_chatcommand("/whois", {
	params = "<player> [v]",
	description = "Returns player information, use v for full record.",
	privs = {ban_admin = true},
	func = function(name, param)
		local list = {}
		for word in param:gmatch("%S+") do
			list[#list+1] = word
		end
		if #list < 1 then
			return false, "usage: /whois <player> [v]"
		end
		local pname = list[1]
		local id = get_id(pname)
		if not id then
			return false, "The player \"" .. pname .. "\" did not join yet."
		end
		local names = name_records(id)
		local ips = address_records(id)
		local msg = "\n" .. minetest.colorize("#FFC000", "Names: ")
		local n, a = {}, {}
		for i, v in ipairs(names) do
			n[#n+1] = v.name
		end
		for i, v in ipairs(ips) do
			a[#a+1] = v.ip
		end
		msg = msg .. table.concat(n, ", ")
		if #list > 1 and list[2] == "v" then
			msg = msg .. minetest.colorize("#FFC000", "IP Addresses: ")
			msg = msg .. "\n" .. table.concat(a, ", ")
		else
			msg = msg .. "\n" .. minetest.colorize("#FFC000", "Last IP Address: ")
			msg = msg .. a[1]
		end
		return true, minetest.colorize("#FFC000", "Info for: ") .. pname .. msg
	end,
})

--[[
#######################
###  API Functions  ###
#######################
]]

-- Ban function
-- @param name string
-- @param source string
-- @param reason string
-- @param expires alphanumerical duration string or integer
-- @return bool
-- @return msg string
sban.ban = function(name, source, reason, expires)
	-- check params are valid
	assert(type(name) == 'string')
	assert(type(source) == 'string')
	assert(type(reason) == 'string')
	if expires and type(expires) == 'string' then
		expires = parse_time(expires)
	elseif expires and type(expires) == "integer" then
		local ts = os.time()
		if expires < ts then
			expires = ts + expires
		end
	end
	if name == owner then
		return false, 'insufficient privileges!'
	end
	local id = get_id(name)
	if not id then
		return false, ("No records exist for %s"):format(name)
	elseif bans[id] then
		-- only one active ban per id is reqd!
		return false, ("An active ban already exist for %s"):format(name)
	end
	-- ban player
	create_ban_record(name, source, reason, expires)
	return true, ("Banned %s."):format(name)
end

-- Unban function
-- @param name string
-- @param source name string
-- @param reason string
-- @return bool and msg string or nil
sban.unban = function(name, source, reason)
	-- check params are valid
	assert(type(name) == 'string')
	assert(type(source) == 'string')
	assert(type(reason) == 'string')
	-- look for records by id
	local id = get_id(name)
	if id then
		if not bans[id] then
			return false, ("No active ban record for "..name)
		end
		update_ban_record(id, name, reason, name)
		return true, ("Unbanned %s."):format(name)
	else
		return false, ("No records exist for %s"):format(name)
	end
end

-- Fetch ban status for a player name or ip address
-- @param name_or_ip string
-- @return bool
sban.ban_status = function(name_or_ip)
	assert(type(name_or_ip) == 'string')
	local id = get_id(name_or_ip)
	return bans[id] ~= nil
end

-- Fetch ban status for a player name or ip address
-- @param name_or_ip string
-- @return keypair table record
sban.ban_record = function(name_or_ip)
	assert(type(name_or_ip) == 'string')
	local id = get_id(name_or_ip)
	if id then
		return bans[id]
	end
end

-- Fetch active bans
-- @return keypair table of active bans
sban.list_active = function()
	return bans
end

--[[
############################
###  Register callbacks  ###
############################
]]

-- Register callback for shutdown event
minetest.register_on_shutdown(function()
	db:close()
end)

-- Register callback for prejoin event
minetest.register_on_prejoinplayer(function(name, ip)

	-- known player?
	local id = get_id(name) or get_id(ip)

	if not id then return end -- unknown player

	t_id[name] = {
		id = id,
		ip = ip,
		ts = os.time()
	}

	-- whitelist bypass
	if WL[name] or WL[ip] then
		minetest.log("action", "[sban] " .. name .. " whitelist login")
		return
	end

	if not dev and owner_id and owner_id == id then return end -- owner bypass

	local data = bans[id]

	if not data then
		-- check names per id
		if names_per_id then
			-- names per id
			local names = name_records(id)
			-- allow existing
			for _,v in ipairs(names) do
				if v.name == name then return end
			end
			-- check player isn't exceeding account limit
			if #names >= names_per_id then
				-- create string list
				local msg = ""
				for _,v in ipairs(names) do
					msg = msg..v.name..", "
				end
				msg = msg:sub(1, msg:len() - 2) -- trim trailing ','
				return ("\nYou exceeded the limit of accounts ("..
				names_per_id..").\nYou already have the following accounts:\n"
				..msg)
			end
		end
		-- check ip's per id
		if ip_limit then
			local t = address_records(id)
			for _,v in ipairs(t) do
				if v.ip == ip then return end
			end
			if #t >= ip_limit then
				return "\nYou exceeded the limit of ip addresses for an account!"
			end
		end

	else
		-- check for ban expiry
		local date

		if type(data.expires) == "number" and data.expires ~= 0 then
			-- temp ban
			if os.time() > data.expires then
				-- clear temp ban
				update_ban_record(data.id, "sban", "ban expired", name)
				return
			end
			date = hrdf(data.expires)
		else
			date = "the end of time"
		end
		return ("Banned: Expires: %s, Reason: %s"):format(date, data.reason)
	end

end)

-- Register callback for join event
minetest.register_on_joinplayer(function(player)

	local name = player:get_player_name()
	local buf = t_id[name]
	local id, ip

	if not buf then
		id = get_id(name)
		ip = minetest.get_player_ip(name)
	else
		id = buf.id
		ip = buf.ip
		clean_join_cache(name)
	end

	if not ip then return end

	manage_hotlist(name)
	trim_cache()

	if not id then
		-- unknown name
		id = get_id(ip) -- ip search
		if not id then
			-- no records, create one
			id = create_player_record(name, ip)
			if not owner_id and name == owner then
				owner_id = id -- initialise
			end
			return
		else
			-- new name record for a known id
			add_name(id, name)
			return
		end
	else
		-- check ip record
		local target_id = get_id(ip)
		if not target_id then
			-- unknown ip
			add_ip(id, ip) -- new ip record
		elseif target_id ~= id then
			-- ip registered to another id!
			manage_idv_record(id, target_id, ip)
			update_idv_status(ip)
		else
			update_address(id, ip)
		end
		-- update record timestamp
		update_login(id, name)
	end
end)
