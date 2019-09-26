# API functions

Sban has a few simple but powerful global functions you can access from your mods.

Ban

	sban.ban(name, source, reason, expires)
	@param name string - reqd
	@param source string - reqd
	@param reason string - reqd
	@param expires alphanumerical duration string or integer
	@return bool
	@return msg string

Unban

	sban.unban(name, source, reason)
	@param name string
	@param source name string
	@param reason string
	@return bool
	@return msg string

Ban status

	sban.ban_status(name_or_ip)
	@param name_or_ip string
	@return bool

Ban record

	sban.ban_record(name_or_ip)
	@param name_or_ip string
	@return keypair table record OR nil

Active bans

	sban.list_active()
	@return keypair table of active bans
