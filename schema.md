The database contains 5 tables;

bans
playerdata
players
whitelist
version

The players table holds the uid for the player

bans:
id          INTEGER NOT NULL,
name        VARCHAR (50),
source      VARCHAR (50),
created     INTEGER,
reason      STRING (300),
expires     INTEGER,
u_source    VARCHAR (50),
u_date      INTEGER,
active      BOOLEAN,
last_pos    VARCHAR (50)

players:
id  INTEGER  PRIMARY KEY AUTOINCREMENT,
ban BOOLEAN

playerdata:
id          INTEGER,
name        VARCHAR (50),
ip          VARCHAR (50),
created     INTEGER,
last_login  INTEGER


version:
rev VARCHAR(50)

whitelist:
name    VARCHAR(50),
source  VARCHAR(50),
created INTEGER
