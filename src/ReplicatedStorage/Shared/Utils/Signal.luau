--!strict
-- Signal serveur minimal.
--
-- Un BindableEvent ferait le travail, mais il serialise ses arguments et
-- impose une frontiere d'instance la ou on veut juste appeler des fonctions
-- dans le meme VM. Celui-ci est une table de rappels : pur, testable, et il
-- transmet les tables par reference.
--
-- Les erreurs des abonnes sont isolees : un HUD qui explose ne doit pas
-- empecher EnemyService d'apprendre que la traque a commence.

local Signal = {}

export type Handler = (...any) -> ()

export type Connection = {
	signal: Signal,
	handler: Handler,
	connected: boolean,
}

export type Signal = {
	handlers: { Connection },
}

function Signal.new(): Signal
	return { handlers = {} }
end

function Signal.connect(signal: Signal, handler: Handler): Connection
	local connection: Connection = {
		signal = signal,
		handler = handler,
		connected = true,
	}
	table.insert(signal.handlers, connection)
	return connection
end

function Signal.disconnect(connection: Connection)
	if not connection.connected then
		return
	end
	connection.connected = false

	local handlers = connection.signal.handlers
	local index = table.find(handlers, connection)
	if index then
		table.remove(handlers, index)
	end
end

function Signal.fire(signal: Signal, ...: any)
	-- Copie de la liste : un abonne qui se desabonne pendant l'emission
	-- decalerait les indices et ferait sauter le suivant.
	local snapshot = table.clone(signal.handlers)
	for _, connection in snapshot do
		if connection.connected then
			local ok, err = pcall(connection.handler, ...)
			if not ok then
				warn(`[Signal] un abonne a leve : {err}`)
			end
		end
	end
end

function Signal.count(signal: Signal): number
	return #signal.handlers
end

function Signal.clear(signal: Signal)
	for _, connection in signal.handlers do
		connection.connected = false
	end
	table.clear(signal.handlers)
end

return Signal
