--[[
	Kristal Anka modelini üretir: lune run src/build.luau   (kristalanka/ klasöründen)
	Çıktı: KristalAnka.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; kuş -Z yönüne bakar, zemin y = 0. Kuş yerden yaklaşık 14
	stud yükseklikte süzülür. Tüyler cam kristal kıymıklarıdır: her biri iki WedgePart'tan oluşan,
	tabanı geniş, ucu sivri bir üçgen. Parçaların kemiğe göre konumları "AnkaRig" ModuleScript'ine
	veri olarak yazılır.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3
local Enum = roblox.Enum
local ColorSequence, ColorSequenceKeypoint = roblox.ColorSequence, roblox.ColorSequenceKeypoint
local NumberSequence, NumberSequenceKeypoint = roblox.NumberSequence, roblox.NumberSequenceKeypoint
local NumberRange = roblox.NumberRange

local function V(x: number, y: number, z: number)
	return Vector3.new(x, y, z)
end
local rad = math.rad

-- Tekrarlanabilir rastgelelik (Park–Miller): her derlemede aynı model çıkar.
local seed = 5050505
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (görseldeki şeffaf buz-beyaz kristal, parlak ışık noktaları) ───
local RGB = Color3.fromRGB
local C = {
	body = RGB(200, 222, 250),
	feather = RGB(214, 232, 255),
	featherCool = RGB(190, 214, 248),
	shine = RGB(235, 245, 255),
	beak = RGB(180, 206, 240),
	claw = RGB(226, 236, 250),
	light = RGB(255, 255, 255),
}
local GLASS_BODY = 0.25
local GLASS_FEATHER = 0.35
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "KristalAnka"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 16)
model:SetAttribute("AnimasyonHizi", 1)

local folders = {}
local function folder(name: string)
	if not folders[name] then
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		folders[name] = f
	end
	return folders[name]
end

-- ─── İskelet ───
type Bone = { name: string, parent: number, pivot: any }
local bones: { Bone } = {}
local boneIndex: { [string]: number } = {}
local function addBone(name: string, parent: string?, pivot)
	table.insert(bones, { name = name, parent = if parent then boneIndex[parent] else 0, pivot = pivot })
	boneIndex[name] = #bones
end
local function pivotOf(name: string)
	return bones[boneIndex[name]].pivot
end

-- ─── Parça yardımcıları ───
local rigParts = {} -- { name, bone, cf }
local counters = {}
local function uniqueName(prefix: string): string
	counters[prefix] = (counters[prefix] or 0) + 1
	return prefix .. counters[prefix]
end

local function basePart(class: string, prefix: string, group: string, bone: string?, cf, size, color, material, opts)
	opts = opts or {}
	local p = Instance.new(class)
	p.Name = uniqueName(prefix)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = opts.query ~= false
	p.CastShadow = opts.shadow ~= false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.Glass
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts.reflectance then
		p.Reflectance = opts.reflectance
	end
	p.Parent = folder(group)
	if bone then
		table.insert(rigParts, { name = p.Name, bone = bone, cf = cf })
	end
	return p
end

local function ellipsoid(prefix, group, bone, cf, size, color, material, opts)
	local p = basePart("Part", prefix, group, bone, cf, size, color, material, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

--- `pos` konumunda, -Z'si (LookVector) `look` yönüne bakan çerçeve. Lune 0.10'daki CFrame.lookAt
--- eğik yönlerde yanlış sonuç verdiği için fromMatrix ile kuruyoruz.
local function lookFrame(pos, look, upHint)
	look = look.Unit
	local up = upHint or V(0, 1, 0)
	if math.abs(look:Dot(up.Unit)) > 0.92 then
		up = if math.abs(look.Z) < 0.9 then V(0, 0, 1) else V(1, 0, 0)
	end
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- a ile b arasına gerilmiş elips.
local function segment(prefix, group, bone, a, b, w, h, color, material, opts)
	opts = opts or {}
	local len = (b - a).Magnitude * (opts.extend or 1.2)
	return ellipsoid(prefix, group, bone, lookFrame((a + b) / 2, b - a, opts.up), V(w, h, len), color, material, opts)
end

--- Pençe/gaga ucu: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
local function spike(prefix, group, bone, pos, out, back, height, length, thickness, color, material, opts)
	out = out.Unit
	back = (back - out * back:Dot(out)).Unit
	local right = out:Cross(back).Unit
	local cf = CFrame.fromMatrix(pos + out * (height / 2), right, out, back)
	return basePart("WedgePart", prefix, group, bone, cf, V(thickness, height, length), color, material, opts)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

--- a, b, c noktalarından geçen üçgeni iki WedgePart ile çizmek için CFrame ve boyutlar (X = kalınlık, çağırana kalır).
local function triangle(a, b, c)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return CFrame.fromMatrix((a + b) / 2, right, up, back), V(0, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back), V(0, height, math.abs(ac:Dot(back)))
end

--- Kristal tüy kıymığı: tabanı `base`te `width` genişliğinde, ucu `tip`te sivri, düz yüzü `normal`e bakan üçgen.
local function shard(prefix, group, bone, base, tip, width, normal, thickness, color, transparency)
	local along = (tip - base).Unit
	local side = normal:Cross(along).Unit
	local cf0, s0, cf1, s1 = triangle(base - side * (width / 2), base + side * (width / 2), tip)
	local opts = { transparency = transparency or GLASS_FEATHER, reflectance = 0.15, shadow = false }
	local a = basePart("WedgePart", prefix, group, bone, cf0, V(thickness, s0.Y, s0.Z), color or C.feather, M.Glass, opts)
	local b = basePart("WedgePart", prefix, group, bone, cf1, V(thickness, s1.Y, s1.Z), color or C.feather, M.Glass, opts)
	return a, b
end

--- Kanat tüyü: tabanı `base`te, `dir` yönünde uzanan, ortası en geniş yassı cam yaprak. Düz yüzü `up`a bakar.
local function vane(group, bone, base, dir, length, width, up, color)
	dir = dir.Unit
	return ellipsoid("Tuy", group, bone, lookFrame(base + dir * (length * 0.5), dir, up), V(width, 0.18, length), color or C.feather, M.Glass,
		{ transparency = GLASS_FEATHER, reflectance = 0.2, shadow = false })
end

--- Tüyün ortasından geçen ince parlak çizgi (kristalin ışıldayan sırtı).
local function rachis(group, bone, base, tip)
	return segment("Isilti", group, bone, base, base + (tip - base) * 0.85, 0.12, 0.12, C.shine, M.Neon,
		{ extend = 1.0, transparency = 0.25, shadow = false, query = false })
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("govde", nil, V(0, 14.0, 0.0))
addBone("gogus", "govde", V(0, 15.0, -2.6))
addBone("boyun1", "gogus", V(0, 16.2, -4.2))
addBone("boyun2", "boyun1", V(0, 17.6, -5.1))
addBone("bas", "boyun2", V(0, 18.8, -5.8))
local headFrame = CFrame.new(pivotOf("bas")) * CFrame.Angles(rad(-10), 0, 0)
local function H(x, y, z)
	return headFrame * V(x, y, z)
end
local function HD(x, y, z)
	return headFrame:VectorToWorldSpace(V(x, y, z))
end
local function HCF(x, y, z)
	return headFrame * CFrame.new(x, y, z)
end
addBone("gaga", "bas", H(0, -0.2, -0.9))
addBone("tepe", "bas", H(0, 0.6, 0.4))
addBone("kuyruk", "govde", V(0, 12.8, 4.2))

local WING = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	WING[side] = {
		s = s,
		root = V(s * 1.5, 15.6, -2.2),
		elbow = V(s * 7.5, 16.8, -0.8),
		wrist = V(s * 13.5, 17.8, 0.0),
		tip = V(s * 19.5, 18.6, 0.6),
	}
	addBone("kanatKol" .. side, "gogus", WING[side].root)
	addBone("kanatOnkol" .. side, "kanatKol" .. side, WING[side].elbow)
	addBone("kanatEl" .. side, "kanatOnkol" .. side, WING[side].wrist)
	addBone("bacak" .. side, "govde", V(s * 0.9, 12.4, 1.0))
	addBone("ayak" .. side, "bacak" .. side, V(s * 1.0, 9.2, -0.2))
end

-- Uzun kuyruk kurdeleleri: her biri 4 kemikli bir zincir; dinlenme pozunda geriye ve aşağı kıvrılır.
local STREAMERS = {
	{ yaw = -0.42, pitch = -0.22 },
	{ yaw = -0.2, pitch = -0.14 },
	{ yaw = 0.02, pitch = -0.2 },
	{ yaw = 0.24, pitch = -0.12 },
	{ yaw = 0.44, pitch = -0.26 },
}
local SEGMENT = 6
local streamerPoints = {}
for k, st in STREAMERS do
	local p = V(st.yaw * 1.2, 12.5, 5.0)
	local points = { p }
	local yaw, pitch = st.yaw, st.pitch
	for i = 1, 4 do
		addBone("kurdele" .. k .. "_" .. i, if i == 1 then "kuyruk" else "kurdele" .. k .. "_" .. (i - 1), p)
		local dir = V(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
		p += dir * SEGMENT
		table.insert(points, p)
		yaw *= 1.12
		pitch -= 0.06
	end
	streamerPoints[k] = points
end

-- ═════════════════════════════ GÖVDE, BOYUN VE BAŞ ═════════════════════════════
local bodyLine = {
	{ V(0, 12.6, 4.6), 1.9, 1.7, "kuyruk" },
	{ V(0, 13.4, 2.0), 3.3, 3.2, "govde" },
	{ V(0, 14.3, -0.6), 4.2, 4.2, "govde" },
	{ V(0, 15.0, -2.8), 4.4, 4.6, "gogus" },
	{ V(0, 16.0, -4.1), 2.9, 3.0, "boyun1" },
	{ V(0, 17.4, -5.0), 1.8, 1.9, "boyun2" },
	{ V(0, 18.6, -5.7), 1.6, 1.7, "bas" },
}
local bodyParts = {}
for i = 1, #bodyLine - 1 do
	local a, b = bodyLine[i], bodyLine[i + 1]
	table.insert(bodyParts, segment("Govde", "Govde", a[4], a[1], b[1], (a[2] + b[2]) / 2 + 0.3, (a[3] + b[3]) / 2 + 0.3, C.body, M.Glass,
		{ extend = 1.55, transparency = GLASS_BODY, reflectance = 0.2 }))
end
ellipsoid("Gogus", "Govde", "gogus", CFrame.new(0, 14.6, -2.6), V(4.6, 5.0, 5.0), C.body, M.Glass, { transparency = GLASS_BODY, reflectance = 0.2 })

-- gövdeyi ve boynu saran küçük kristal pullar: geriye doğru yatık kıymıklar
for i = 1, #bodyLine - 2 do
	local a, b = bodyLine[i], bodyLine[i + 1]
	local dir = (a[1] - b[1]).Unit -- kuyruğa doğru
	for k = 0, 7 do
		local ang = rad(k * 45 + (if i % 2 == 0 then 22 else 0) + jitter(8))
		local radial = (V(math.cos(ang), math.sin(ang), 0) - dir * V(math.cos(ang), math.sin(ang), 0):Dot(dir)).Unit
		local r = (b[2] + b[3]) / 4 * 0.85
		local base = b[1] + radial * r
		local tip = base + dir * (1.6 + (a[2] * 0.35)) + radial * 0.35
		shard("Pul", "Govde", b[4], base, tip, 1.0 + a[2] * 0.16, radial, 0.12, if k % 2 == 0 then C.feather else C.featherCool, 0.3)
	end
end

-- baş: kafatası, gaga, ışık saçan gözler ve geriye uzanan tepe tüyleri
local skull = ellipsoid("Kafa", "Bas", "bas", HCF(0, 0.2, -0.4), V(1.7, 1.6, 2.2), C.body, M.Glass, { transparency = 0.2, reflectance = 0.2 })
ellipsoid("Gaga", "Bas", "bas", HCF(0, -0.05, -1.9), V(0.7, 0.62, 2.0), C.beak, M.Glass, { transparency = 0.15, reflectance = 0.25 })
spike("GagaUcu", "Bas", "bas", H(0, 0.05, -2.75), HD(0, -0.55, -1), HD(0, -1, 0), 0.7, 0.35, 0.36, C.beak, M.Glass, { transparency = 0.15 })
ellipsoid("AltGaga", "Bas", "gaga", HCF(0, -0.35, -1.75), V(0.58, 0.32, 1.6), C.beak, M.Glass, { transparency = 0.15, reflectance = 0.25 })
local eyes = {}
for _, s in { 1, -1 } do
	table.insert(eyes, ellipsoid("Goz", "Bas", "bas", HCF(s * 0.66, 0.38, -0.95), V(0.3, 0.34, 0.4), C.light, M.Neon, { shadow = false }))
	-- yanak kıymıkları
	for k = 0, 2 do
		local base = H(s * 0.7, 0.1 - k * 0.3, -0.2 + k * 0.1)
		shard("Yanak", "Bas", "bas", base, base + HD(s * 0.35, -0.1, 1.2 + k * 0.2), 0.5, HD(s, 0.2, 0), 0.1, C.feather, 0.3)
	end
end
-- ışık çekirdeği: görseldeki gibi başın yanında parlayan yıldız
local core = ellipsoid("IsikCekirdegi", "Bas", "bas", HCF(0.75, 0.42, -1.0), V(0.45, 0.45, 0.45), C.light, M.Neon, { shadow = false, query = false })
-- tepe: başın arkasından yukarı ve geriye yelpaze gibi açılan uzun kıymıklar
for i, x in { -0.55, -0.35, -0.15, 0.05, 0.25, 0.45, 0.6 } do
	local base = H(x * 0.6, 0.65, 0.1 + math.abs(x) * 0.3)
	local length = 2.4 + 1.6 * math.sin(i / 7 * math.pi) + jitter(0.3)
	local tip = base + HD(x * 1.4, 0.75, 1.0).Unit * length
	shard("Tepe", "Bas", "tepe", base, tip, 0.42, HD(1, 0, 0), 0.1, C.feather, 0.25)
end

-- ═════════════════════════════ KANATLAR ═════════════════════════════
local trailParts = {}
for _, side in { "L", "R" } do
	local w = WING[side]
	local s = w.s
	local kol, onkol, el = "kanatKol" .. side, "kanatOnkol" .. side, "kanatEl" .. side
	local group = "Kanat" .. side
	-- kanat kemikleri
	segment("KanatKemik", group, kol, w.root, w.elbow, 1.2, 1.0, C.body, M.Glass, { extend = 1.15, transparency = GLASS_BODY })
	segment("KanatKemik", group, onkol, w.elbow, w.wrist, 0.9, 0.75, C.body, M.Glass, { extend = 1.15, transparency = GLASS_BODY })
	segment("KanatKemik", group, el, w.wrist, w.tip, 0.7, 0.55, C.body, M.Glass, { extend = 1.1, transparency = GLASS_BODY })
	local span = (w.tip - w.root).Unit
	local up = span:Cross(V(0, 0, 1)) * -s -- kanadın üst yüzü
	if up.Y < 0 then
		up = -up
	end

	-- içteki tüyler (kol): geriye bakan
	for i = 0, 4 do
		local base = lerp(w.root, w.elbow, 0.2 + i * 0.19) - up * 0.1
		vane(group, kol, base, V(s * 0.05, -0.05, 1), 5.0 + i * 0.3, 2.0, up)
	end
	-- ikincil tüyler (önkol): geriye ve hafifçe dışa bakan uzun yapraklar
	for i = 0, 8 do
		local t = i / 8
		local base = lerp(w.elbow, w.wrist, t) - up * (0.15 + i * 0.03)
		vane(group, onkol, base, V(s * (0.03 + t * 0.18), -0.05, 1), 6.6 + 0.6 * math.sin(t * math.pi), 2.1, up,
			if i % 2 == 0 then C.feather else C.featherCool)
	end
	-- birincil tüyler (el): bilekten uca yelpaze gibi dışa açılır, en uzunları dış kenarda
	for i = 0, 9 do
		local t = i / 9
		local base = lerp(w.wrist, w.tip, t * 0.92) - up * (0.2 + i * 0.03)
		local angle = rad(16 + t * 66)
		local dir = V(s * math.sin(angle), -0.06, math.cos(angle)).Unit
		local length = 7 + 3.4 * math.sin(t * math.pi * 0.85)
		vane(group, el, base, dir, length, 1.9 - t * 0.4, up, if i % 2 == 0 then C.feather else C.featherCool)
		local line = rachis(group, el, base + up * 0.1, base + up * 0.1 + dir * length)
		if i >= 8 then
			table.insert(trailParts, line)
		end
	end
	-- örtü tüyleri: kemiğin üstünde iki sıra kısa yaprak; ön kenarda küçük kıymıklar
	for row = 1, 2 do
		local n = if row == 1 then 13 else 10
		for i = 0, n - 1 do
			local t = i / (n - 1)
			local p = if t < 0.34 then lerp(w.root, w.elbow, t / 0.34) elseif t < 0.8 then lerp(w.elbow, w.wrist, (t - 0.34) / 0.46) else lerp(w.wrist, w.tip, (t - 0.8) / 0.2 * 0.6)
			local bone = if t < 0.34 then kol elseif t < 0.8 then onkol else el
			if row == 1 then
				vane(group, bone, p + up * 0.3 + V(0, 0, 0.4), V(s * 0.08, -0.05, 1), 3.4 + rand() * 0.6, 1.7, up, C.featherCool)
			else
				shard("Ortu", group, bone, p + up * 0.45 - V(0, 0, 0.4), p + up * 0.5 + V(s * 0.2, -0.05, 1.9), 1.1, up, 0.12, C.feather, 0.3)
			end
		end
	end
end

-- ═════════════════════════════ KUYRUK ═════════════════════════════
-- kuyruk yelpazesi
for i = 0, 5 do
	local x = (i - 2.5) * 0.35
	local base = V(x, 12.6, 4.4)
	local tip = base + V(x * 1.6, -1.6 - math.abs(x) * 0.6, 7.0 - math.abs(x))
	shard("KuyrukTuyu", "Kuyruk", "kuyruk", base, tip, 1.1, V(0, 1, -0.2).Unit, 0.14, C.feather)
end
-- kurdeleler: ince cam şeritler, eklemlerde boncuklar, uçta kristal damla
local ornaments = {}
for k, points in streamerPoints do
	for i = 1, 4 do
		local bone = "kurdele" .. k .. "_" .. i
		segment("Kurdele", "Kuyruk", bone, points[i], points[i + 1], 0.6, 0.26, C.feather, M.Glass, { extend = 1.08, transparency = 0.3, shadow = false })
		if i > 1 then
			ellipsoid("Boncuk", "Kuyruk", bone, CFrame.new(points[i]), V(0.75, 0.75, 0.75), C.featherCool, M.Glass, { transparency = 0.2, shadow = false })
		end
	end
	local last = "kurdele" .. k .. "_4"
	local dir = (points[5] - points[4]).Unit
	ellipsoid("Damla", "Kuyruk", last, lookFrame(points[5] + dir * 0.5, dir), V(0.95, 0.95, 1.7), C.featherCool, M.Glass, { transparency = 0.2, reflectance = 0.3, shadow = false })
	spike("DamlaUcu", "Kuyruk", last, points[5] + dir * 1.25, dir, V(0, 1, 0), 0.9, 0.5, 0.5, C.featherCool, M.Glass, { transparency = 0.2, shadow = false })
	table.insert(ornaments, ellipsoid("DamlaIsigi", "Kuyruk", last, CFrame.new(points[5] + dir * 0.5), V(0.4, 0.4, 0.4), C.light, M.Neon, { shadow = false, query = false }))
end

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local hip, ankle = pivotOf("bacak" .. side), pivotOf("ayak" .. side)
	ellipsoid("Uyluk", "Bacaklar", "bacak" .. side, CFrame.new(hip + V(0, 0.3, 0.1)), V(1.5, 2.2, 1.9), C.body, M.Glass, { transparency = GLASS_BODY })
	segment("Incik", "Bacaklar", "bacak" .. side, hip, ankle, 0.5, 0.5, C.body, M.Glass, { extend = 1.05, transparency = 0.2 })
	-- üç ön parmak ve bir arka parmak, uçlarında kıvrık pençeler
	for _, toe in { { -0.45, -1 }, { 0, -1 }, { 0.45, -1 }, { 0, 1 } } do
		local dir = V(s * toe[1], -0.45, toe[2]).Unit
		local tip = ankle + dir * (if toe[2] > 0 then 0.9 else 1.5)
		segment("Parmak", "Bacaklar", "ayak" .. side, ankle, tip, 0.32, 0.32, C.body, M.Glass, { extend = 1.1, transparency = 0.2 })
		spike("Pence", "Bacaklar", "ayak" .. side, tip, V(dir.X, -0.9, dir.Z), -dir, 0.8, 0.35, 0.22, C.claw, M.Glass, { transparency = 0.1 })
	end
end

-- ═════════════════════════════ EFEKTLER ═════════════════════════════
local function seq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(kps)
end
local function nums(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end
local function emitter(parent, name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for k, v in props do
		if k ~= "attributes" then
			(e :: any)[k] = v
		end
	end
	for k, v in props.attributes or {} do
		e:SetAttribute(k, v)
	end
	e.Parent = parent
	return e
end
local function attachment(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GLITTER = seq({ { 0, RGB(255, 255, 255) }, { 0.5, RGB(210, 235, 255) }, { 1, RGB(170, 210, 255) } })

-- başın yanındaki ışık: parlama ve nokta ışık (çığlıkta alevlenir)
emitter(core, "Parilti", {
	Texture = SPARKLE, Color = GLITTER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 2.6 }, { 1, 0.8 } }),
	Transparency = nums({ { 0, 0.2 }, { 1, 1 } }), Lifetime = NumberRange.new(0.25, 0.4), Rate = 14, Speed = NumberRange.new(0, 0),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), LockedToPart = true,
})
local headLight = Instance.new("PointLight")
headLight.Name = "BasIsigi"
headLight.Color = RGB(220, 238, 255)
headLight.Range = 18
headLight.Brightness = 2
headLight.Shadows = false
headLight.Parent = core

-- kanat uçlarından ve kurdele damlalarından dökülen pırıltı izi
for _, part in trailParts do
	local a = attachment(part, "Iz", CFrame.new(0, 0, -part.Size.Z / 2))
	emitter(a, "IzParilti", {
		Texture = SPARKLE, Color = GLITTER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.5 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.9, 1.5), Rate = 22, Speed = NumberRange.new(0, 1), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), Acceleration = V(0, -0.6, 0),
	})
end
for _, part in ornaments do
	emitter(part, "IzParilti", {
		Texture = SPARKLE, Color = GLITTER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.4 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.8, 1.2), Rate = 8, Speed = NumberRange.new(0, 0.6), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
	})
end

-- çığlık: göğüsten her yöne saçılan ışık patlaması ve gagadan fışkıran kristal kırıntıları
local chest = folders["Govde"]:FindFirstChild("Gogus1")
emitter(chest, "IsikPatlamasi", {
	Texture = SPARKLE, Color = GLITTER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 1.2 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.8, 1.6), Rate = 0, Speed = NumberRange.new(20, 45), SpreadAngle = Vector2.new(180, 180),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-180, 180), Drag = 2,
	attributes = { CiglikPatlamasi = true, Adet = 90 },
})
local beakOut = attachment(skull, "CiglikCikisi", CFrame.new(0, -0.3, -2.4))
emitter(beakOut, "KristalKirintisi", {
	Texture = SPARKLE, Color = GLITTER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.8 }, { 1, 0.1 } }),
	Lifetime = NumberRange.new(0.5, 0.9), Rate = 60, Speed = NumberRange.new(16, 28), SpreadAngle = Vector2.new(25, 25),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), EmissionDirection = Enum.NormalId.Front,
	Enabled = false, attributes = { CiglikEfekti = true },
})

-- ═════════════════════════════ KÖK VE ÇARPIŞMA ═════════════════════════════
local root = Instance.new("Part")
root.Name = "Kok"
root.Anchored = true
root.CanCollide = false
root.CanTouch = false
root.CanQuery = false
root.Transparency = 1
root.Size = V(6, 0.2, 6)
root.CFrame = CFrame.new(0, 0, 0)
root.Parent = model
model.PrimaryPart = root

local body = Instance.new("Part")
body.Name = "GovdeCarpisma"
body.Anchored = true
body.CanCollide = true
body.CanTouch = false
body.Transparency = 1
body.CastShadow = false
body.Size = V(4, 4.6, 9)
body.CFrame = CFrame.new(0, 14.6, -0.8) * CFrame.Angles(rad(-15), 0, 0)
body.Parent = folder("Carpisma")

-- ═════════════════════════════ RIG VERİSİ ═════════════════════════════
local function fmt(n: number): string
	local str = string.format("%.5f", n)
	str = str:gsub("0+$", ""):gsub("%.$", "")
	if str == "-0" then
		str = "0"
	end
	return str
end
local function v3(v)
	return string.format("Vector3.new(%s, %s, %s)", fmt(v.X), fmt(v.Y), fmt(v.Z))
end
local function cfLiteral(cf)
	local out = {}
	for _, n in { cf:GetComponents() } do
		table.insert(out, fmt(n))
	end
	return "CFrame.new(" .. table.concat(out, ", ") .. ")"
end

local lines = { "-- Bu tablo build.luau tarafından üretildi; elle düzenlemeyin.", "local Rig = {}", "", "Rig.bones = {" }
for _, b in bones do
	local parentPivot = if b.parent > 0 then bones[b.parent].pivot else V(0, 0, 0)
	table.insert(lines, string.format("\t{ name = %q, parent = %d, rel = %s },", b.name, b.parent, v3(b.pivot - parentPivot)))
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "Rig.parts = {")
for _, rp in rigParts do
	local pivot = pivotOf(rp.bone)
	table.insert(lines, string.format("\t{ name = %q, bone = %d, offset = %s },", rp.name, boneIndex[rp.bone], cfLiteral(CFrame.new(-pivot.X, -pivot.Y, -pivot.Z) * rp.cf)))
end
table.insert(lines, "}")
table.insert(lines, string.format("Rig.STREAMERS = %d", #STREAMERS))
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "AnkaRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. fs.readFile("src/rig.luau")
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("KristalAnka.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("KristalAnka.rbxmx yazıldı: %d parça, %d kemik", count, #bones))
for name, f in folders do
	print(string.format("  %-10s %d", name, #f:GetChildren()))
end
