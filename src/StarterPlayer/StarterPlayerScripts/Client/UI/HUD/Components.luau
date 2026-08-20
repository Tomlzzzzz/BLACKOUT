--!strict
-- Fabrique de composants du HUD.
--
-- La consigne est explicite : creer des composants reutilisables plutot que
-- de monter chaque panneau a la main. Tout ce qui se repete dans la maquette
-- vit ici — le cadre technique, les equerres d'angle, la jauge segmentee, le
-- libelle espace, les pictogrammes.
--
-- Aucun widget ne cree de Frame nu ni ne declare de couleur : il assemble ces
-- briques. C'est ce qui garantit qu'un changement de direction artistique
-- reste un changement de Theme.

local Theme = require(script.Parent.Theme)

local Components = {}

-- ------------------------------------------------------------- Base -----

function Components.new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local new = Components.new

-- Espacement des lettres, absent de Roblox. Reserve aux petits libelles en
-- capitales : c'est ce qui les fait lire comme des etiquettes d'instrument
-- plutot que comme du texte courant.
function Components.spaced(text: string): string
	return (text:gsub(".", "%0 "):gsub("%s+$", ""))
end

-- 12400 -> "12 400", avec une espace fine insecable.
function Components.group(value: number): string
	local text = tostring(math.floor(math.max(0, value)))
	local out, count = "", 0
	for index = #text, 1, -1 do
		out = text:sub(index, index) .. out
		count += 1
		if count % 3 == 0 and index > 1 then
			out = "\u{202F}" .. out
		end
	end
	return out
end

-- ------------------------------------------------------------ Textes ----

export type LabelProps = {
	text: string?,
	size: number?,
	color: Color3?,
	font: Enum.Font?,
	align: Enum.TextXAlignment?,
	transparency: number?,
	position: UDim2?,
	anchor: Vector2?,
	sizeUDim: UDim2?,
	zIndex: number?,
}

function Components.label(props: LabelProps, parent: Instance): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = props.text or "",
		Font = props.font or Theme.font.label,
		TextSize = props.size or Theme.size.label,
		TextColor3 = props.color or Theme.color.info,
		TextTransparency = props.transparency or 0,
		TextXAlignment = props.align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = props.sizeUDim or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.fromScale(0, 0),
		AnchorPoint = props.anchor or Vector2.new(0, 0),
		ZIndex = props.zIndex or 2,
	}, parent) :: TextLabel
	return label
end

-- BROUILLAGE DE TEXTE. Source unique.
--
-- Le bloc de vitaux avait le sien, la panique generale en avait un autre,
-- moins agressif : deux coins de l'ecran qui se degradaient differemment
-- racontent deux appareils, pas un seul en train de lacher. Ils partagent
-- desormais cette fonction, et donc exactement le meme grain.
--
-- 45 % des caracteres NON BLANCS sont remplaces. Les espaces sont
-- preserves : c'est ce qui garde la silhouette du mot lisible pendant que
-- son contenu part en morceaux, et qui distingue un signal degrade d'une
-- bouillie de symboles.
function Components.scramble(text: string): string
	local glyphs = Theme.glitchGlyphs
	local out = {}
	for index = 1, #text do
		local char = text:sub(index, index)
		if char ~= " " and math.random() < 0.45 then
			local pick = math.random(1, #glyphs)
			table.insert(out, glyphs:sub(pick, pick))
		else
			table.insert(out, char)
		end
	end
	return table.concat(out)
end

-- ------------------------------------------------------------ Cadres ----

export type Panel = {
	root: Frame,
	body: Frame,
	brackets: { Frame },
}

-- Le cadre technique de la maquette : fond presque noir translucide, filet
-- d'un pixel, et quatre equerres d'angle optionnelles.
--
-- `bracketColor` nil = pas d'equerres. Elles sont reservees aux panneaux
-- importants (contrat, vitaux) ; les mettre partout les banaliserait.
function Components.panel(
	props: { [string]: any },
	parent: Instance,
	bracketColor: Color3?
): Panel
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = Theme.panel.background,
		BorderSizePixel = 0,
		Visible = false,
	}
	for key, value in props do
		defaults[key] = value
	end

	local root = new("Frame", defaults, parent) :: Frame
	new("UICorner", { CornerRadius = UDim.new(0, Theme.panel.corner) }, root)
	new("UIStroke", {
		Color = Theme.color.border,
		Thickness = Theme.panel.border,
		Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, root)

	local body = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -Theme.space.panelPadding * 2, 1, -Theme.space.panelPadding),
		Position = UDim2.new(0, Theme.space.panelPadding, 0, Theme.space.panelPadding * 0.5),
		ZIndex = 2,
	}, root) :: Frame

	local brackets: { Frame } = {}
	if bracketColor then
		local length = Theme.panel.bracketLength
		local thickness = Theme.panel.bracketThickness
		for _, corner in {
			{ x = 0, y = 0, ax = 0, ay = 0 },
			{ x = 1, y = 0, ax = 1, ay = 0 },
			{ x = 0, y = 1, ax = 0, ay = 1 },
			{ x = 1, y = 1, ax = 1, ay = 1 },
		} do
			local anchor = Vector2.new(corner.ax, corner.ay)
			local position = UDim2.fromScale(corner.x, corner.y)

			table.insert(brackets, new("Frame", {
				BackgroundColor3 = bracketColor,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				AnchorPoint = anchor,
				Position = position,
				Size = UDim2.fromOffset(length, thickness),
				ZIndex = 3,
			}, root))

			table.insert(brackets, new("Frame", {
				BackgroundColor3 = bracketColor,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				AnchorPoint = anchor,
				Position = position,
				Size = UDim2.fromOffset(thickness, length),
				ZIndex = 3,
			}, root))
		end
	end

	return { root = root, body = body, brackets = brackets }
end

-- ------------------------------------------------------------ Jauges ----

export type Bar = {
	root: Frame,
	segments: { Frame },
	ghosts: { Frame },
}

-- Jauge segmentee, sur DEUX couches.
--
-- La couche fantome, derriere, retient la valeur precedente et la rattrape
-- avec du retard. C'est le procede des barres de vie de jeu de combat : on
-- voit COMBIEN on vient de perdre, pas seulement ce qu'il reste. Sans elle,
-- une perte de trente points et une perte de trois se ressemblent.
function Components.bar(props: { [string]: any }, color: Color3, parent: Instance): Bar
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Theme.bar.height),
	}
	for key, value in props do
		defaults[key] = value
	end

	local root = new("Frame", defaults, parent) :: Frame
	local count = Theme.bar.segments
	local segments: { Frame } = {}
	local ghosts: { Frame } = {}

	-- Largeur en echelle, gouttiere en pixels : la jauge suit la largeur du
	-- panneau sans que l'espacement grossisse avec elle.
	local width = 1 / count
	for index = 1, count do
		local position = UDim2.fromScale((index - 1) * width, 0)
		local size = UDim2.new(width, -Theme.bar.gap, 1, 0)

		table.insert(ghosts, new("Frame", {
			BackgroundColor3 = Theme.color.danger,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = size,
			Position = position,
			ZIndex = 2,
		}, root))

		table.insert(segments, new("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = Theme.bar.emptyTransparency,
			BorderSizePixel = 0,
			Size = size,
			Position = position,
			ZIndex = 3,
		}, root))
	end

	return { root = root, segments = segments, ghosts = ghosts }
end

-- Remplit une jauge. `ghost` est la valeur en cours de rattrapage ; passer
-- nil ou une valeur inferieure a `fraction` masque la couche fantome.
--
-- Le dernier bloc partiel est rendu par une transparence intermediaire : sans
-- cela une jauge a dix blocs ne saurait afficher que des multiples de dix
-- pour cent.
function Components.setBar(bar: Bar, fraction: number, color: Color3?, ghost: number?, ghostColor: Color3?)
	local count = #bar.segments
	local exact = math.clamp(fraction, 0, 1) * count
	local ghostExact = math.clamp(ghost or 0, 0, 1) * count

	for index, segment in bar.segments do
		local filled = exact - (index - 1)

		if filled > 0 then
			segment.BackgroundColor3 = color or segment.BackgroundColor3
			segment.BackgroundTransparency = if filled >= 1 then 0 else 0.55 * (1 - filled)
		else
			-- Bloc vide : gris neutre, jamais la couleur de la ressource. Une
			-- jauge d'armure a zero teintee en rouge sur toute sa longueur se
			-- lit « pleine et en alerte », soit l'inverse de la verite.
			segment.BackgroundColor3 = Theme.color.separator
			segment.BackgroundTransparency = Theme.bar.emptyTransparency
		end

		-- Fantome : uniquement entre la valeur reelle et la valeur retardee.
		local phantom = bar.ghosts[index]
		if phantom then
			local trailing = ghostExact - (index - 1)
			if trailing > 0 and filled < 1 then
				phantom.BackgroundColor3 = ghostColor or Theme.color.danger
				phantom.BackgroundTransparency = if trailing >= 1 then 0.35 else 0.35 + 0.5 * (1 - trailing)
			else
				phantom.BackgroundTransparency = 1
			end
		end
	end
end

-- --------------------------------------------------------- Separateur ---

function Components.separator(props: { [string]: any }, parent: Instance): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.color.separator,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 2,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("Frame", defaults, parent) :: Frame
end

-- ------------------------------------------------------ Pictogrammes ----
--
-- Dessines avec des Frames plutot qu'importes comme images.
--
-- Deux raisons : aucun asset n'a besoin d'etre televerse ni modere avant que
-- le HUD soit testable, et un pictogramme vectoriel reste net a toutes les
-- resolutions. Ils sont volontairement schematiques — a 14 pixels, un dessin
-- detaille devient une tache.

local function box(parent: Instance, color: Color3, size: UDim2, position: UDim2, rotation: number?): Frame
	return new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = rotation or 0,
		ZIndex = 3,
	}, parent) :: Frame
end

-- Teinte un pictogramme, remplissages ET contours.
--
-- Les pictogrammes melangent des Frames pleines et des UIStroke ; recolorer
-- seulement les premieres laissait les contours figes dans leur couleur
-- d'origine, ce qui se voyait des qu'une jauge passait au rouge.
function Components.tintIcon(icon: Frame, color: Color3)
	for _, child in icon:GetDescendants() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
		elseif child:IsA("UIStroke") then
			child.Color = color
		elseif child:IsA("ImageLabel") then
			child.ImageColor3 = color
		end
	end
end

-- Conteneur au trait, commun aux quatre symboles vitaux.
--
-- C'EST LUI QUI FAIT LE JEU D'ICONES.
--
-- Les versions precedentes melangeaient formes pleines et contours sans
-- langage commun : quatre dessins sans parente, qui se lisaient comme quatre
-- taches. Ici les quatre partagent le meme boitier, la meme graisse de trait
-- et le meme rayon d'angle ; seul le symbole interieur change. C'est ce qui
-- transforme des dessins isoles en instrumentation.
local function shell(parent: Instance, color: Color3): Frame
	local frame = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
	}, parent) :: Frame
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, frame)
	new("UIStroke", { Color = color, Thickness = 1.2, Transparency = 0.35 }, frame)
	return frame
end

-- Conteneur carre pour un pictogramme.
--
-- Coordonnees en ECHELLE, sur une grille conceptuelle de 1x1 : le symbole
-- reste net a n'importe quelle taille de rendu.
function Components.icon(kind: string, color: Color3, props: { [string]: any }, parent: Instance): Frame
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
		ZIndex = 3,
	}
	for key, value in props do
		defaults[key] = value
	end
	local root = new("Frame", defaults, parent) :: Frame

	-- Un identifiant renseigne remplace le dessin. Le dessin reste le repli :
	-- un asset absent ou modere ne doit jamais laisser un carre vide.
	local assetId = Theme.iconAssets[kind]
	if assetId and assetId ~= 0 then
		new("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = `rbxassetid://{assetId}`,
			ImageColor3 = color,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, root)
		return root
	end

	if kind == "health" then
		shell(root, color)
		-- Croix pleine, branches larges : a cette taille, une croix fine
		-- disparait contre le trait du boitier.
		box(root, color, UDim2.fromScale(0.46, 0.16), UDim2.fromScale(0.5, 0.5))
		box(root, color, UDim2.fromScale(0.16, 0.46), UDim2.fromScale(0.5, 0.5))
	elseif kind == "armor" then
		shell(root, color)
		-- Chevron : deux barres inclinees qui se rejoignent en pointe basse.
		-- Plus lisible qu'un ecusson miniature, et c'est le signe militaire
		-- consacre pour la protection.
		box(root, color, UDim2.fromScale(0.14, 0.42), UDim2.fromScale(0.37, 0.45), -32)
		box(root, color, UDim2.fromScale(0.14, 0.42), UDim2.fromScale(0.63, 0.45), 32)
	elseif kind == "stamina" then
		shell(root, color)
		-- Eclair : deux fuseaux decales fermes par deux pointes.
		box(root, color, UDim2.fromScale(0.15, 0.34), UDim2.fromScale(0.56, 0.36), 22)
		box(root, color, UDim2.fromScale(0.15, 0.34), UDim2.fromScale(0.44, 0.64), 22)
		box(root, color, UDim2.fromScale(0.13, 0.13), UDim2.fromScale(0.62, 0.24), 45)
		box(root, color, UDim2.fromScale(0.13, 0.13), UDim2.fromScale(0.38, 0.76), 45)
	elseif kind == "battery" then
		-- La pile garde son propre boitier : sa forme EST le symbole, lui
		-- imposer le conteneur commun ferait un cadre dans un cadre.
		local body = box(root, color, UDim2.fromScale(0.78, 0.60), UDim2.fromScale(0.42, 0.5))
		body.BackgroundTransparency = 1
		new("UICorner", { CornerRadius = UDim.new(0, 2) }, body)
		new("UIStroke", { Color = color, Thickness = 1.2, Transparency = 0.35 }, body)

		box(root, color, UDim2.fromScale(0.08, 0.24), UDim2.fromScale(0.87, 0.5))

		for index = 1, 3 do
			box(root, color, UDim2.fromScale(0.14, 0.32), UDim2.fromScale(0.23 + (index - 1) * 0.19, 0.5))
		end
	elseif kind == "clock" then
		local ring = box(root, color, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
		ring.BackgroundTransparency = 1
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		new("UIStroke", { Color = color, Thickness = 1.2, Transparency = 0.1 }, ring)
		box(root, color, UDim2.fromScale(0.1, 0.34), UDim2.fromScale(0.5, 0.36))
	elseif kind == "weather" then
		local a = box(root, color, UDim2.fromScale(0.55, 0.45), UDim2.fromScale(0.4, 0.42))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, a)
		local b = box(root, color, UDim2.fromScale(0.45, 0.38), UDim2.fromScale(0.68, 0.48))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
		box(root, color, UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.5, 0.66))
	elseif kind == "pin" then
		local head = box(root, color, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.38))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, head)
		box(root, color, UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.5, 0.72), 45)
	elseif kind == "rifle" then
		box(root, color, UDim2.fromScale(0.92, 0.16), UDim2.fromScale(0.5, 0.44))
		box(root, color, UDim2.fromScale(0.14, 0.34), UDim2.fromScale(0.42, 0.68))
		box(root, color, UDim2.fromScale(0.3, 0.12), UDim2.fromScale(0.2, 0.6), 18)
	elseif kind == "pistol" then
		box(root, color, UDim2.fromScale(0.68, 0.18), UDim2.fromScale(0.52, 0.4))
		box(root, color, UDim2.fromScale(0.18, 0.42), UDim2.fromScale(0.36, 0.66), 12)
	elseif kind == "medkit" then
		local body = box(root, color, UDim2.fromScale(0.9, 0.68), UDim2.fromScale(0.5, 0.54))
		body.BackgroundTransparency = 0.45
		new("UICorner", { CornerRadius = UDim.new(0, 2) }, body)
		box(root, color, UDim2.fromScale(0.42, 0.14), UDim2.fromScale(0.5, 0.54))
		box(root, color, UDim2.fromScale(0.14, 0.42), UDim2.fromScale(0.5, 0.54))
	elseif kind == "grenade" then
		local body = box(root, color, UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.5, 0.58))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, body)
		box(root, color, UDim2.fromScale(0.24, 0.16), UDim2.fromScale(0.5, 0.18))
	elseif kind == "utility" then
		box(root, color, UDim2.fromScale(0.56, 0.76), UDim2.fromScale(0.46, 0.52))
		box(root, color, UDim2.fromScale(0.14, 0.2), UDim2.fromScale(0.8, 0.52))
	end

	return root
end

return Components
