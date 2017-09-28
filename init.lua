-- sban mod for minetest voxel game
-- designed and coded by shivajiva101@hotmail.com

local WP = minetest.get_worldpath()
local ie = minetest.request_insecure_environment()

if not ie then
	error("insecure environment inaccessible"..
	" - make sure this mod has been added to minetest.conf!")
end

-- requires library for db access
ie.require("lsqlite3")

minetest.register_privilege("ban_admin", "Player bans admin")

local db_version = "0.1"
local whitelist = {} -- cache
local db = sqlite3.open(WP.."/sban.sqlite") -- connection
local expiry = minetest.setting_get("sban.ban_max") or {}
local owner = minetest.setting_get("name")
local display_max = minetest.setting_get("sban.display_max") or 10
local t_units = {
	s = 1, m = 60, h = 3600,
	D = 86400, W = 604800, M = 2592000, Y = 31104000,
	[""] = 1,
}

--[[
#########################
###  Parse Functions  ###
#########################
]]
-- convert value to seconds, copied from xban2 mod
local function parse_time(t)
	local s = 0
	for n, u in t:gmatch("(%d+)([smhDWMY]?)") do
		s = s + (tonumber(n) * (t_units[u] or 1))
	end
	return s
end
-- human readable date format - converts UTC
local function hrdf(t)
    if type(t) == "number" then
        return (t and os.date("%c", t))
    end
end

--[[
##########################
###  Database: Tables  ###
##########################
]]

createDb = "CREATE TABLE IF NOT EXISTS bans (id INTEGER, "
    .."name VARCHAR(50), source VARCHAR(50), created INTEGER, "
    .."reason VARCHAR(300), expires INTEGER, u_source VARCHAR(50), "
    .."u_reason VARCHAR(300), u_date INTEGER, active BOOLEAN, "
    .."last_pos VARCHAR(50));\n"
    .."CREATE TABLE IF NOT EXISTS playerdata (id INTEGER, "
    .."name VARCHAR(50), ip VARCHAR(50), created INTEGER, "
    .."last_login INTEGER);\nCREATE TABLE IF NOT EXISTS players ("
    .."id INTEGER PRIMARY KEY AUTOINCREMENT, ban BOOLEAN);\n"
    .."CREATE TABLE IF NOT EXISTS whitelist (name VARCHAR(50), "
    .."source VARCHAR(50), created INTEGER);\n"
    .."CREATE TABLE IF NOT EXISTS version (rev VARCHAR(20));\n"
db:exec(createDb)

--[[
###########################
###  Database: Queries  ###
###########################
]]

local function get_id(player_name)
    local q = ([[
        SELECT players.id
        FROM players
        INNER JOIN
        playerdata ON playerdata.id = players.id
        WHERE playerdata.name = '%s']]
    ):format(player_name)
    for row in db:nrows(q) do
        return row.id
    end
end

local function next_id()
	-- construct
    local q = [[SELECT seq FROM sqlite_sequence WHERE name= "players"]]
	-- returns an integer for last id
    for row in db:nrows(q) do
        return row.seq + 1 -- next id
    end
end

local function is_banned(name_or_ip)
	-- initialise
    local r = {}
	local q = ([[
    SELECT  players.id,
            playerdata.ip,
            bans.reason,
            bans.expires
    FROM    players
            INNER JOIN
            bans ON players.id = bans.id
            INNER JOIN
            playerdata ON playerdata.id = players.id
    WHERE   players.ban = 'true' AND
            playerdata.name = '%s' AND
			bans.active = 'true';]]
    ):format(name_or_ip)

	if string.find(name_or_ip, "%.") ~= nil then
		q = ([[
	    SELECT  players.id,
	            playerdata.ip,
	            bans.reason,
	            bans.expires
	    FROM    players
	            INNER JOIN
	            bans ON players.id = bans.id
	            INNER JOIN
	            playerdata ON playerdata.id = players.id
	    WHERE   players.ban = 'true' AND
	            playerdata.ip = '%s' AND
		    bans.active = 'true';]]
	    ):format(name_or_ip)
	end
	-- fill return table
    for row in db:nrows(q) do
        r[#r+1] = row
    end
    return r
end

local function find_ban(id)
	-- initialise
    local r = {}
	-- construct
    local q = ([[
        SELECT
            bans.id,
            bans.name,
            bans.reason,
            bans.created,
            bans.source,
            bans.expires,
            bans.u_source,
            bans.u_reason,
            bans.u_date,
            bans.active,
            bans.last_pos
       FROM bans
       WHERE bans.id = '%s']]
   ):format(id)
	-- fill return table
    for row in db:nrows(q) do
        r[#r+1] = row
    end
    return r
end

local function find_records(name_or_ip)
    -- initialise
    local r = {}
    -- construct
    local q = ([[
    SELECT  players.id,
            players.ban,
            playerdata.name,
            playerdata.ip,
            playerdata.created,
            playerdata.last_login
    FROM    players
    INNER JOIN
            playerdata ON playerdata.id = players.id
    WHERE   playerdata.name = '%s' OR playerdata.ip = '%s']]
    ):format(name_or_ip, name_or_ip)
	-- fill return table
    for row in db:nrows(q) do
        r[#r+1] = row
    end
    return r
end

local function find_records_by_id(id)
	-- initialise
    local r = {}
	-- construct
    local q = ([[
    SELECT  players.id,
            players.ban,
            playerdata.name,
            playerdata.ip,
            playerdata.created,
            playerdata.last_login
    FROM    players
    INNER JOIN
            playerdata ON playerdata.id = players.id
    WHERE   playerdata.id = '%s'
    ]]):format(id)
	-- fill return table
    for row in db:nrows(q) do
        r[#r+1] = row
    end
    return r
end

local function get_whitelist()
    local r = {}
    local query = "SELECT * FROM whitelist"
    for row in db:nrows(query) do
        r[row.name] = true
    end
    return r
end

local function get_version()
    local query = "SELECT * FROM version"
    for row in db:nrows(query) do
        return row.rev
    end
end

local function display_record(name, p_name)
    local id = get_id(p_name)
    local r = find_records_by_id(id)
    if #r == 0 then
        minetest.chat_send_player(name, "No records for "..p_name)
        return
    end
    local privs = minetest.get_player_privs(name)
    -- records loaded, display
    local idx = 1
    if #r > display_max then
        idx = #r - display_max
        minetest.chat_send_player(name,
        "Player records: "..#r.." (showing last "..display_max.." records)")
    else
        minetest.chat_send_player(name,
        "Player records: "..#r)
    end
    if privs.ban_admin == true then
        for i=idx,#r do
            -- format utc values
            local d1 = hrdf(r[i].created)
            local d2 = hrdf(r[i].last_login)
            minetest.chat_send_player(name,
            ("[%s] Name: %s IP: %s Created: %s Last login: %s"
            ):format(i, r[i].name, r[i].ip, d1, d2))
        end
    else
        for i=idx,#r do
            local d1 = hrdf(r[i].created)
            local d2 = hrdf(r[i].last_login)
            minetest.chat_send_player(name,
            ("[%s] Name: %s Created: %s Last login: %s"
            ):format(i,r[i].name, d1, d2))
        end
    end

    local t = find_ban(id) or {}
    if #t > 0 then
        minetest.chat_send_player(name,"Ban records: "..#t)
        local ban = t[#t].active
        for i,e in ipairs(t) do
            local d1 = hrdf(e.created)
            local expires
            if type(e.expires) == "number" then
                expires = hrdf(e.expires)
            else
                expires = "never"
            end
            if type(e.u_date) == "number"
            and e.u_date > 0 then
                local d2 = hrdf(e.u_date)
                minetest.chat_send_player(name,
                ("[%s] Name: %s Created: %s Banned by: %s Reason: %s Expires: %s"
            ):format(i, e.name, d1, e.source, e.reason, expires))
                minetest.chat_send_player(name,
                ("[%s] Unbanned by: %s Reason: %s Time: %s"
            ):format(i,e.u_source,e.u_reason,d2))
            else
                minetest.chat_send_player(name,
                ("[%s] Name: %s Created: %s Banned by: %s Reason: %s Expires: %s"
            ):format(i, e.name, d1, e.source, e.reason, expires))
            end
        end
        minetest.chat_send_player(name, "Banned: "..ban)
    else
        minetest.chat_send_player(name,"No Ban records!")
    end
end

--[[
###########################
###  Database: Inserts  ###
###########################
]]

local function create_entry(player_name, ip_address)
    -- players table id is auto incremented
    -- id,ban
    db:exec[[
        INSERT INTO players (ban)
        VALUES ('false')
        ]]
    -- retrieve id
    local id = next_id() - 1
    -- create timestamp
    local ts = os.time()
    -- id,name,ip,created,last_login
    q = ([[
        INSERT INTO playerdata
        VALUES (%s,'%s','%s',%s,%s)
        ]]):format(id, player_name, ip_address, ts, ts)
    db:exec(q)
    return id
end

local function add_player(id, player_name, ip_address)
    local ts = os.time()
    local q = ([[
        INSERT INTO playerdata
        VALUES (%s,'%s','%s',%s,%s)
        ]]):format(id, player_name, ip_address, ts, ts)
    db:exec(q)
end

local function add_whitelist(source, name_or_ip)
    local q = ([[
    INSERT INTO whitelist
    VALUES ('%s', '%s', %i)
    ]]):format(name_or_ip, source, os.time())
    db:exec(q)
	-- cache
	whitelist[name_or_ip] = true
end

local function ban_player(name, source, reason, expires)
    local id = get_id(name)
    local player = minetest.get_player_by_name(name)
    -- players: id,ban
    local q = ([[
        UPDATE players SET ban = 'true' WHERE id = '%s'
        ]]):format(id)
    db:exec(q)
    -- initialise last position
    local last_pos = ""
    if player then
        last_pos = minetest.pos_to_string(vector.round(player:getpos()))
    end
    -- id,name,source,created,reason,expires,u_source,u_reason,
    -- u_date,active,last_pos
    q = ([[
        INSERT INTO bans
        VALUES ('%s','%s','%s','%s','%s','%s','','','','true','%s')
        ]]):format(id, name, source, os.time(), reason, expires, last_pos)
    db:exec(q)

    local msg_k,msg_l
    -- create kick & log messages
    if expires ~= "" then
        local date = hrdf(expires)
		msg_k = ("Banned: Expires: %s, Reason: %s"
        ):format(date, reason)
        msg_l = ("[sban] %s temp banned by %s reason: %s"
        ):format(name,source,reason)
	else
		msg_k = ("Banned: Reason: %s"):format(reason)
        msg_l = ("[sban] %s banned by %s reason: %s"
        ):format(name,source,reason)
	end
    minetest.log("action", msg_l)
    -- kick all names associated with the player
    local records = find_records(name)
	for i,v in ipairs(records) do
		minetest.kick_player(v.name, msg_k)
	end
end

local function set_version(str)
    local q = ([[
        INSERT INTO version
        VALUES ('%s')
        ]]):format(str)
    db:exec(q)
end

--[[
###########################
###  Database: Updates  ###
###########################
]]

local function update_login(player_name)
    local q = ([[
        UPDATE playerdata SET last_login = %s WHERE name = '%s'
        ]]):format(os.time(), player_name)
    db:exec(q)
end

local function unban_player(id, name, source, reason)
    local q = ([[
        UPDATE players SET ban = '%s' WHERE id = '%s'
        ]]):format(false, id)
    db:exec(q)
    q = ([[
        UPDATE bans SET
        active = '%s',
        u_source = '%s',
        u_reason = '%s',
        u_date = '%i'
        WHERE id = '%i' AND name = '%s'
    ]]):format(false,source,reason,os.time(),id,name)
    db:exec(q)
    -- log event
    minetest.log("action",
    ("[sban] %s unbanned by %s reason: %s"):format(name,source,reason))
end

--[[
##################################
###  Database: Delete Records  ###
##################################
]]

local function del_ban_record(name)
    local q = ([[
    DELETE FROM bans WHERE name = '%s'
    ]]):format(name)
    db:exec(q)
end

local function del_whitelist(name_or_ip)
    local q = ([[
    DELETE FROM whitelist WHERE name = '%s'
    ]]):format(name_or_ip)
    db:exec(q)
	-- remove from cache
	whitelist[name_or_ip] = {}
end
--[[
#######################
###  File Handling  ###
#######################
]]

local function load_xban(filename)
  local f, e = ie.io.open(WP.."/"..filename, "rt")
  if not f then
    return false, "Unable to load xban2 database:"..e
  end
  local cont = f:read("*a")
  f:close()
  if not cont then
    return false, "Unable to load xban2 database: Read failed"
  end
  local t = minetest.deserialize(cont)
  if not t then
    return false, "xban2 database: Deserialization failed"
  end
  return t
end

local function load_ipban()
	local f, e = ie.io.open(WP.."/ipban.txt")
	if not f then
		return false, "Unable to open `ipban.txt': "..e
	end
	local content = f:read("*a")
	f:close()
	return content
end

local function save_sql(txt)
	local file = ie.io.open(WP.."/xban.sql", "a")
	if file then
	  file:write(txt)
	  file:close()
	end
end

local function del_sql()
	ie.os.remove(WP.."/xban.sql")
end

--[[
##############
###  Misc  ###
##############
]]

-- initialise db version
if get_version() == nil then
    set_version(db_version)
end

whitelist = get_whitelist()

local function import_xban(name, file_name)

    local t,e = load_xban(file_name)
    -- exit with error message
    if not t then
        return t,e
    end
    local id = next_id()
    print("processing "..#t.." records")
    -- iterate the xban2 data
    for i,e in ipairs(t) do
        -- only process banned entries
        if e.banned == true then

            local names = {}
    		local ip = {}
    		local last_seen = e.last_seen
    		local last_pos = e.last_pos or ""
    		--local id = nil
    		local q = ""
            -- each entry in xban db contains a names field, both IP and names
            -- are stored in this field, split into 2 tables
            for k,v in pairs(e.names) do
                if string.find(k, "%.") ~= nil then
    				table.insert(ip, k)
                else
    				table.insert(names, k)
                end
            end
            -- check for existing entry by name
            local chk = true
            for i,v in ipairs(names) do
                q = ([[SELECT * FROM playerdata WHERE name = '%s']]):format(v)
                for row in db:nrows(q) do
                    chk = false
                    break
                end
            end
            if chk then
                -- process the entry
        		-- construct INSERT for players table
        		q = [[INSERT INTO players (ban) VALUES ('true');]]
        		db:exec(q)

                -- If there are more names than IP's use the last entry for
                -- the reamining entries IP. If there are more IP's use the
                -- last name for the remaining entries
                local ts = os.time()
        		if table.getn(names) > table.getn(ip) then
        			local tbl = table.getn(ip)
        			local idx = 0
        			for i,v in ipairs(names) do
        				idx = i
        				if idx > tbl then idx = tbl end
        				-- id,name,ip,created,last_login
        				q = ([[
        					INSERT INTO playerdata
        					VALUES (%s,'%s','%s',%s,%s)
        					]]):format(id,v,ip[idx],ts,last_seen)
        				db:exec(q)
        			end
        		elseif table.getn(ip) > table.getn(names) then
        			local tbl = table.getn(names)
        			local idx = 0
        			for i,v in ipairs(ip) do
        				idx = i
        				if idx > tbl then idx = tbl end
        				-- id,name,ip,created,last_login
        				q = ([[
        					INSERT INTO playerdata
        					VALUES (%s,'%s','%s',%s,%s)
        					]]):format(id,names[idx],v,ts,last_seen)
        				db:exec(q)
        			end
        		else
        			for i,v in ipairs(names) do
        				-- id,name,ip,created,last_login
        				q = ([[
        					INSERT INTO playerdata
        					VALUES (%s,'%s','%s',%s,%s)
        				]]):format(id,v,ip[i],ts,last_seen)
        				db:exec(q)
        			end
        		end
        		-- id,name,source,created,reason,expires,u_source,u_reason,
                -- u_date,active,last_pos
                -- convert position to string
                if last_pos.y then
					last_pos = parse_pos(last_pos)
                    last_pos = minetest.pos_to_string(last_pos)
                end
    			for i,v in ipairs(e.record) do
    				local expires = v.expires or ""
                    local reason = string.gsub(v.reason, "%'", "")
    				q = ([[
    					INSERT INTO bans
    					VALUES ('%s','%s','%s','%s','%s','%s','','','','%s','%s')
    				]]):format(id,names[1],v.source,v.time,reason,expires,e.banned,last_pos)
                    db:exec(q)
    			end
                id = id +1
            end
        end
    end
end

local function import_ipban(source)
    local contents = load_ipban()
    if not contents then
        return false
    end
    local data = string.split(contents, "\n")
    for i,v in ipairs(data) do
        -- each line consists of an ip, separator and name
        local ip, name = v:match("([^|]+)%|(.+)")
        if ip and name then
            -- check for an existing entry by name
            local chk = true
            local q = ([[SELECT * FROM
			playerdata WHERE name = '%s']]):format(name)
            for row in db:nrows(q) do
                chk = false
                break
            end
            if chk then
                -- create player entry
            	create_entry(name,ip)
            end
            -- check for existing ban
            local r = is_banned(name)
            if #r == 0 then
                -- create ban entry - name,source,reason,expires
                ban_player(name,source,"imported from ipban.txt",'')
            end
        end
    end
end

local function sql_string(id,entry)

    local names = {}
	local ip = {}
	local last_seen = entry.last_seen
	local last_pos = entry.last_pos or ""
    local ts = os.time()

    -- names field includes both IP and names data, sort into 2 tables
    for k,v in pairs(entry.names) do
        if string.find(k, "%.") ~= nil then
			table.insert(ip, k)
        else
			table.insert(names, k)
        end
    end

	-- construct INSERT for players table based on ban status
	local q = ("INSERT INTO players VALUES ('%s','%s');\n"
	):format(id,entry.banned)

    -- case: more names than IP's uses the last entry for reamining names
	if #names > #ip then
		local t = #ip
		local idx = 0
		for i,v in ipairs(names) do
			idx = i
			if idx > t then idx = t end
			-- id,name,ip,created,last_login
			q = q..("INSERT INTO playerdata VALUES ('%s','%s','%s','%s','%s');\n"
        ):format(id,v,ip[idx],ts,last_seen)
		end
    -- case: more ip's than names uses last entry for remaining ip's
	elseif #ip > #names then
		local t = #names
		local idx = 0
		for i,v in ipairs(ip) do
			idx = i
			if idx > t then idx = t end
			-- id,name,ip,created,last_login
            q = q..("INSERT INTO playerdata VALUES ('%s','%s','%s','%s','%s');\n"
        ):format(id,names[idx],v,ts,last_seen)
		end
    -- case: number of ip's and names is equal
	else
		for i,v in ipairs(names) do
			-- id,name,ip,created,last_login
            q = q..("INSERT INTO playerdata VALUES ('%s','%s','%s','%s','%s');\n"
        ):format(id,v,ip[i],ts,last_seen)
		end
	end

	if entry.reason then
        -- convert position
        if last_pos.y then
			last_pos = vector.round(last_pos)
            last_pos = minetest.pos_to_string(last_pos)
        end
        -- id,name,source,created,reason,expires,u_source,u_reason,u_date,active,last_pos
		for i,v in ipairs(entry.record) do
			local expires = v.expires or ""
            local reason = string.gsub(v.reason, "%'", "")
            reason = string.gsub(reason, "%:%)", "")
			q = q..("INSERT INTO bans VALUES ('%s','%s','%s','%i','%s','%s','','','','%s','%s');\n"
        ):format(id,names[1],v.source,v.time,reason,expires,entry.banned,last_pos)
		end
	end
    return q
end

local function export_sql(filename)
	-- load the db, iterate in reverse order and remove each
	-- record to balance the memory use otherwise large files
	-- cause lua OOM error
	local dbi = load_xban(filename)
	local id = next_id()
	-- reverse the contents with #entries/2
	for i=1, math.floor(#dbi / 2) do
      local tmp = dbi[i]
      dbi[i] = dbi[#dbi - i + 1]
      dbi[#dbi - i + 1] = tmp
    end
	-- add create tables string
	save_sql(createDb)
	-- add single transaction
	save_sql("BEGIN;\n")
	-- process records
	for i = #dbi,1,-1 do
		-- contains data?
		if dbi[i] then
			local str = sql_string(id,dbi[i]) -- sql statement
			save_sql(str)
			dbi[i] = nil -- housekeeping
			id = id + 1
		end
	end
	-- close transaction
	save_sql("END;")
end

--[[
###########################
###  Register Commands  ###
###########################
]]

minetest.override_chatcommand("ban", {
	description = "Bans a player from the server",
	params = "<player> <reason>",
	privs = { ban=true },
	func = function(name, params)
		local player_name, reason = params:match("(%S+)%s+(.+)")
		-- check params are present
		if not (player_name and reason) then
			return false, "Usage: /ban <player> <reason>"
		end
		-- protect owner
		if player_name == owner then
			return false, "Insufficient privileges!"
		end
		-- banned player?
		local query = is_banned(player_name)
		if #query > 0 then
			return true, ("%s is already banned!"):format(player_name)
		end
		-- limit ban?
		if type(expiry) ~= "table" then
			expiry = parse_time(expiry) + os.time()
		else
			expiry = ''
		end
		-- handle known/unknown players dependant on privs
		local query = find_records(player_name)
		if #query > 0 then
			-- existing player
			-- Params: name, source, reason, expires
			ban_player(player_name, name, reason, expiry)
			return true, ("Banned %s."):format(player_name)
		else
			local privs = minetest.get_player_privs(name)
			-- assert normal behaviour without ban_admin priv
			if not privs.ban_admin then
				return false, "Player doesn't exist!"
			end
			-- create entry before ban
			create_entry(player_name,"0.0.0.0") -- arbritary ip
			ban_player(player_name, name, reason, expiry)
			return true, ("Banned nonexistent player %s."):format(player_name)
		end
	end,
})

minetest.register_chatcommand("ban_dbe", {
	description = "export xban2 db to sql format",
	params = "<filename>",
	privs = {server=true},
	func = function(name, params)
		local filename = params:match("%S+")
		if not filename then
			return false, "Use: /ban_dbe <filename>"
		end
		del_sql()
		export_sql(filename)
		return true, "xban2 dumped to xban.sql file!"
	end
})

minetest.register_chatcommand("ban_dbi", {
	description = "Import bans",
	params = "<filename>",
	privs = {server=true},
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
			local res,err = import_xban(name, filename)
			msg = err
			if res then
				msg = filename.." imported!"
			end
		end
		return true, msg
	end
})

minetest.register_chatcommand("ban_del", {
	description = "Deletes a player's sban records",
	params = "player",
	privs = {server=true},
	func = function(name, params)
		local player_name = params:match("%S+")
		if not player_name then
			return false, "Usage: /ban_del_record <player>"
		end
		del_ban_record(player_name)
		minetest.log("action",
		"ban records for "..player_name.." deleted by "..name)
		return true, player_name.." ban records deleted!"
	end
})

minetest.register_chatcommand("ban_record", {
	description = "Display player sban records",
	params = "<player_or_ip>",
	privs = { ban=true },
	func = function(name, params)
		local playername = params:match("%S+")
		if not playername then
			return false, "Useage: /ban_record <player_name>"
		end
		-- get target and source privs
		local target = find_records_by_id(get_id(playername))
		local source = minetest.get_player_privs(name)
		local chk = false
		-- If the target has server privs on any account
		-- do NOT allow record to be shown unless source
		-- has server priv.
		for i,v in ipairs(target) do
			local privs = minetest.get_player_privs(v.name)
			if privs.server then chk = true break end
		end
		-- if source doesn't have sufficient privs deny
		if not source.server and chk then
			return false, "Insufficient privileges!"
		end
		display_record(name, playername)
		return true
	end
})

minetest.register_chatcommand("ban_wl", {
	description = "Manages the whitelist",
	params = "(add|del|list) <name_or_ip>",
	privs = {server=true},
	func = function(name, params)
		local cmd, name_or_ip = params:match("(%S+)%s+(.+)")
		if not cmd == "list" then
			if not (cmd and name_or_ip) then
				return false, ("Usage: /ban_wl (add|del) "
				.."<name_or_ip> \nor /ban_wl list")
			end
		end
		if cmd == "add" then
			add_whitelist(name_or_ip, name)
			minetest.log("action",
			("%s added %s to whitelist"):format(name, name_or_ip))
			return true, name_or_ip.." added to whitelist!"
		elseif cmd == "del" then
			del_whitelist(name_or_ip)
			minetest.log("action",("%s removed %s from whitelist"
		):format(name, name_or_ip))
			return true, name_or_ip.." removed from whitelist!"
		elseif cmd == "list" then
			if #whitelist > 0 then
				local str = ""
				for k,v in pairs(whitelist) do
					str = str..k.."\n"
				end
				return true, str
			else
				return true, "Whitelist empty!"
			end
		end
	end,
})

minetest.register_chatcommand("tempban", {
	description = "Ban a player temporarily with sban",
	params = "<player> <time> <reason>",
	privs = { ban=true },
	func = function(name, params)
		local player_name, time, reason = params:match("(%S+)%s+(%S+)%s+(.+)")
		if not (player_name and time and reason) then
			return false, "Usage: /tempban <player> <time> <reason>"
		end
		if player_name == owner then
			return false, "Insufficient privileges!"
		end
		-- is player already banned?
		local query = is_banned(player_name)
		if #query > 0 then
			return true, ("%s is already banned!"):format(player_name)
		end
		time = parse_time(time)
		if time < 60 then
			return false, "You must ban for at least 60 seconds."
		end
		local expires = os.time() + time
		query = find_records(player_name)
		if #query > 0 then
			-- existing player
			ban_player(player_name, name, reason, expires)
			return true, ("Banned %s until %s."):format(
				player_name, os.date("%c", expires))
		else
			local privs = minetest.get_player_privs(name)
			-- assert normal behaviour without server priv
			if not privs.ban_admin then
				return false, "Player doesn't exist!"
			end
			-- create entry before ban
			create_entry(player_name,"0.0.0.0")
			ban_player(player_name, name, reason, expires)
			return true, ("Banned nonexistent player %s until %s."
			):format(player_name, os.date("%c", expires))
		end
	end,
})

minetest.override_chatcommand("unban", {
	description = "Unban a player or ip banned with sban",
	params = "<player_or_ip> <reason>",
	privs = { ban=true },
	func = function(name, params)
		local player_name, reason = params:match("(%S+)%s+(.+)")
		if not (player_name and reason) then
			return false, "Usage: /unban <player_or_ip> <reason>"
		end
		-- look for records by id
		local id = get_id(player_name)
		if id then
			local bans = find_ban(id) -- get ban records
			-- look for the active ban
			for i,v in ipairs(bans) do
				if v.active then
					unban_player(id, v.name, name, reason)
					return true, ("Unbanned %s."):format(v.name)
				end
			end
		end
		return false, "no record found for "..player_name
	end,
})

--[[
########################
###  Register Hooks  ###
########################
]]

minetest.register_on_shutdown(function()
    db:close()
end)

minetest.register_on_prejoinplayer(function(name, ip)
	-- check player isn't whitelisted
	if whitelist[name] or whitelist[ip] then
		minetest.log("action", "[sban] "..
		name.." whitelist entry permits login")
		return
	end
	-- retrieve player record
	local record = is_banned(name)
	if #record == 0 then -- no name record
		record = is_banned(ip)
		if #record == 0 then -- no ip record
			return
		end
	end
	local data = record[#record] -- last entry
	local date
	-- check for ban expiry
	if type(data.expires) == "number" then
		--temp ban
		if os.time() > data.expires then
			-- clear temp ban
			unban_player(data.id, name, "sban","ban expired")
			return
		end
		date = hrdf(data.expires)
	else
		date = "the end of time"
	end
	return ("Banned: Expires: %s, Reason: %s"):format(date, data.reason)
end)

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local ip = minetest.get_player_ip(name)
	if not ip then return end
	local record = find_records(name)
	local ip_record = {}
	-- check for player name entry
	if #record == 0 then
		-- no records, check for ip
		ip_record = find_records(ip)
		if #ip_record == 0 then
			-- create new entry
			create_entry(name, ip)
			return
		else
			-- add record [new name]
			add_player(ip_record[1].id, name, ip)
			return
		end
	else
		-- check for ip record
		ip_record = find_records(ip)
		if #ip_record == 0 then
			-- add record [player is using a new ip]
			add_player(record[1].id, name, ip)
			return
		end
		-- update record
		update_login(name)
	end
end)
