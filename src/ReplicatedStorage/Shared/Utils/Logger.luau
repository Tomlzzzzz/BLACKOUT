--!strict
-- Log prefixe par scope, pour retrouver qui parle dans la console Studio.
--
-- Le type est declare avant les methodes (patron LoggerImpl) : sinon
-- `typeof(setmetatable(...))` fige la forme de la table au moment de la
-- declaration, avant que info/warn/error existent, et --!strict rejette
-- ensuite chaque appel `log:info(...)`.

local Logger = {}
Logger.__index = Logger

type LoggerImpl = {
	__index: LoggerImpl,
	info: (self: Logger, message: string) -> (),
	warn: (self: Logger, message: string) -> (),
	error: (self: Logger, message: string) -> (),
}

export type Logger = typeof(setmetatable({} :: { scope: string }, {} :: LoggerImpl))

function Logger.new(scope: string): Logger
	return setmetatable({ scope = scope }, Logger) :: any
end

function Logger.info(self: Logger, message: string)
	print(`[{self.scope}] {message}`)
end

function Logger.warn(self: Logger, message: string)
	warn(`[{self.scope}] {message}`)
end

function Logger.error(self: Logger, message: string)
	-- On ne raise pas : un service casse ne doit pas tuer le boot.
	warn(`[{self.scope}] ERREUR : {message}`)
end

return Logger
