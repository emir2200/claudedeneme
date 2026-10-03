--[[
	Dokuz Kuyruklu Tilki modelini üretir: lune run src/build.luau   (tilki/ klasöründen)
	Çıktı: DokuzKuyrukluTilki.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Gövde, baş, kulaklar, hale ve kuyruklar kemiklere; bacak parçaları bacak bölümlerine bağlıdır.
	Bacak bölümlerinin çerçeveleri oyunda ters kinematikle hesaplanır; parçaların bu çerçevelere
	göre konumları "TilkiRig" ModuleScript'ine veri olarak yazılır.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
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
local seed = 8080808
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (karbeyaz kürk, mavimsi gölgeler, siyah bacaklar, kırmızı ve mavi işaretler) ───
local RGB = Color3.fromRGB
local C = {
	fur = RGB(242, 244, 248),
	shade = RGB(220, 226, 238),
	deep = RGB(196, 204, 222),
	black = RGB(38, 38, 46),
	nose = RGB(24, 22, 28),
	innerEar = RGB(86, 72, 80),
	red = RGB(206, 34, 44),
	mark = RGB(40, 140, 255),
	eye = RGB(70, 190, 245),
	pupil = RGB(16, 22, 34),
	mouth = RGB(140, 70, 84),
	halo = RGB(255, 222, 150),
	haloOrb = RGB(255, 246, 214),
	foxfire = RGB(130, 210, 255),
}
local M = Enum.Material
local FUR = M.Fabric

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "DokuzKuyrukluTilki"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 15)
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
	p.Material = material or FUR
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.transparency then
		p.Transparency = opts.transparency
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

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function ctl(pos, w, h, bone)
	return { pos = pos, w = w, h = h, bone = bone }
end

--- Kontrol noktaları ({ pos, w, h, bone }) boyunca yay uzunluğuyla örnekleyici.
local function chainSampler(controls)
	local samples = {}
	for i = 1, #controls - 1 do
		local c0, c1 = controls[i], controls[i + 1]
		local seg = c1.pos - c0.pos
		local n = math.max(1, math.ceil(seg.Magnitude / 0.2))
		for k = 0, n - 1 do
			local t = k / n
			table.insert(samples, { pos = c0.pos + seg * t, w = lerp(c0.w, c1.w, t), h = lerp(c0.h, c1.h, t), bone = if t < 0.5 then c0.bone else c1.bone })
		end
	end
	local last = controls[#controls]
	table.insert(samples, { pos = last.pos, w = last.w, h = last.h, bone = last.bone })
	local arcs = { 0 }
	for i = 2, #samples do
		arcs[i] = arcs[i - 1] + (samples[i].pos - samples[i - 1].pos).Magnitude
	end
	local total = arcs[#arcs]
	local function at(s)
		s = math.clamp(s, 0, total)
		local i = 1
		while i < #samples - 1 and arcs[i + 1] < s do
			i += 1
		end
		local a, b = samples[i], samples[i + 1]
		local t = if arcs[i + 1] > arcs[i] then (s - arcs[i]) / (arcs[i + 1] - arcs[i]) else 0
		return { pos = lerp(a.pos, b.pos, t), w = lerp(a.w, b.w, t), h = lerp(a.h, b.h, t), bone = if t < 0.5 then a.bone else b.bone }
	end
	local function dir(s)
		return (at(s + 0.3).pos - at(s - 0.3).pos).Unit
	end
	return { at = at, dir = dir, total = total }
end

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir boru.
local function smoothTube(prefix, group, controls, spacing, length, color, material, opts)
	local sampler = chainSampler(controls)
	local half = math.min(length, sampler.total) / 2
	local span = sampler.total - 2 * half
	local count = math.max(1, math.ceil(span / spacing) + 1)
	local made = {}
	for j = 0, count - 1 do
		local s = half + (if count > 1 then span * j / (count - 1) else span / 2)
		local c = sampler.at(s)
		local look = sampler.at(s + half * 0.5).pos - sampler.at(s - half * 0.5).pos
		table.insert(made, ellipsoid(prefix, group, c.bone, lookFrame(c.pos, look), V(c.w, c.h, half * 2), color, material, opts))
	end
	return made, sampler
end

--- `origin`dan `dir` yönünde giden ışının, `origin`ı içine alan elipslerden en dışta çıktığı mesafe.
local function surfaceDistance(parts, origin, dir)
	local best = 0
	for _, p in parts do
		local r = p.Size / 2
		local o = p.CFrame:PointToObjectSpace(origin) / r
		local d = p.CFrame:VectorToObjectSpace(dir) / r
		local a, b, c = d:Dot(d), 2 * o:Dot(d), o:Dot(o) - 1
		local disc = b * b - 4 * a * c
		if c < 0 and disc >= 0 then
			best = math.max(best, (-b + math.sqrt(disc)) / (2 * a))
		end
	end
	return best
end

--- Kürk tutamı: yassı, uca doğru incelen bir elips. Tabanı `base`, `dir` yönünde uzanır; düz yüzü `normal`e bakar.
local function tuft(group, bone, base, dir, normal, length, width, color)
	dir = dir.Unit
	return ellipsoid("Tutam", group, bone, lookFrame(base + dir * (length * 0.45), dir, normal), V(width, 0.42, length), color or C.shade, FUR,
		{ query = false })
end

--- Yüzeye yatık şerit: points = { pos, normal, width, bone }; ardışık noktalar arası yassı elipsler.
local function ribbon(prefix, group, points, thickness, color, material, overlap)
	local made = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b.pos - a.pos).Magnitude
		if len > 1e-3 then
			table.insert(made, ellipsoid(prefix, group, a.bone, lookFrame((a.pos + b.pos) / 2, b.pos - a.pos, (a.normal + b.normal).Unit),
				V((a.width + b.width) / 2, thickness, len * (overlap or 2.2)), color, material, { shadow = false, query = false }))
		end
	end
	return made
end

--- Catmull-Rom eğrisinde bir nokta.
local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

--- Üçgen: tabanı `base`te `width` genişliğinde, ucu `tip`te; düz yüzü `normal`e bakan iki WedgePart.
local function triangle(prefix, group, bone, base, tip, width, normal, thickness, color, material)
	local along = (tip - base).Unit
	local side = normal:Cross(along).Unit
	local a, b, c = base - side * (width / 2), base + side * (width / 2), tip
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
	local w0 = basePart("WedgePart", prefix, group, bone, CFrame.fromMatrix((a + b) / 2, right, up, back), V(thickness, height, math.abs(ab:Dot(back))), color, material)
	local w1 = basePart("WedgePart", prefix, group, bone, CFrame.fromMatrix((a + c) / 2, -right, up, -back), V(thickness, height, math.abs(ac:Dot(back))), color, material)
	return w0, w1
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("govde", nil, V(0, 6.7, 0.3))
addBone("gogus", "govde", V(0, 6.65, -2.2))
addBone("boyun", "gogus", V(0, 7.7, -3.6))
addBone("bas", "boyun", V(0, 9.6, -5.0))
addBone("kalca", "govde", V(0, 6.95, 2.7))
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
addBone("cene", "bas", H(0, -0.5, -0.6))
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	addBone("kulak" .. side, "bas", H(s * 0.62, 0.95, -0.2))
end
local HALO_CENTER = H(0, 0.6, 1.1)
local HALO_AXIS = HD(0, 0, 1)
addBone("hale", "bas", HALO_CENTER)

-- Dokuz kuyruk: kalçanın üstünden yelpaze gibi açılır (φ: -84°…+84°, 0 = dik yukarı).
local TAIL_ROOT = V(0, 7.4, 4.2)
local tails = {}
for k = 1, 9 do
	local phi = rad(-84 + (k - 1) * 21)
	local R = V(math.sin(phi), math.cos(phi), 0)
	local B = V(0, 0, 1)
	local points = {
		TAIL_ROOT + R * 0.3 + B * 0.1,
		TAIL_ROOT + R * 1.6 + B * 1.3,
		TAIL_ROOT + R * 3.7 + B * 2.3,
		TAIL_ROOT + R * 6.0 + B * 2.7,
		TAIL_ROOT + R * 8.2 + B * 2.4,
		TAIL_ROOT + R * 9.4 + B * 1.9,
	}
	local side = if k < 5 then -1 elseif k > 5 then 1 else 0
	local tail = { k = k, R = R, points = points, side = side, bones = {}, phase = k * 0.83,
		fan = if side == 0 then V(0, 0, 1) else V(0, 0, -side), lift = R:Cross(B).Unit }
	for i = 1, 4 do
		local name = "kuyruk" .. k .. "_" .. i
		addBone(name, if i == 1 then "kalca" else "kuyruk" .. k .. "_" .. (i - 1), points[i])
		table.insert(tail.bones, name)
	end
	table.insert(tails, tail)
end

-- ═════════════════════════════ GÖVDE ═════════════════════════════
local bodyParts, body = smoothTube("Govde", "Govde", {
	ctl(V(0, 7.2, 4.3), 1.9, 1.9, "kalca"),
	ctl(V(0, 6.95, 2.7), 2.9, 3.1, "kalca"),
	ctl(V(0, 6.7, 0.3), 2.6, 2.9, "govde"),
	ctl(V(0, 6.65, -2.2), 3.0, 3.5, "gogus"),
	ctl(V(0, 7.7, -3.6), 2.8, 3.0, "boyun"),
	ctl(V(0, 8.8, -4.5), 2.3, 2.4, "boyun"),
	ctl(V(0, 9.6, -5.0), 2.0, 2.0, "bas"),
}, 0.7, 4.0, C.fur, FUR)
local function dorsalAt(s)
	local d = body.dir(s)
	local hint = V(0, 1, 0.6)
	return (hint - d * hint:Dot(d)).Unit
end
local function bodySurface(s, ray)
	local p = body.at(s).pos
	return p + ray * surfaceDistance(bodyParts, p, ray)
end

-- Göğüs yelesi: boynun önünden göğse uzanan, aşağı sarkan katmanlı kürk tutamları
for row = 0, 3 do
	local s = body.total - 2.0 - row * 0.85
	local c = body.at(s)
	local d, n = body.dir(s), dorsalAt(s)
	local front, side = -n, d:Cross(n).Unit
	local count = 9
	for k = 0, count - 1 do
		local a = rad(-85 + k * (170 / (count - 1)) + jitter(6) + (if row % 2 == 0 then 0 else 12))
		local ray = (front * math.cos(a) + side * math.sin(a)).Unit
		local base = bodySurface(s, ray) - ray * 0.35
		local length = (2.0 + row * 0.2) * (0.85 + 0.3 * rand())
		tuft("Govde", c.bone, base, ray * 0.35 + V(jitter(0.25), -1, 0) + d * 0.15, ray, length, length * 0.36, if (k + row) % 4 == 0 then C.shade else C.fur)
	end
end
-- Ense ve omuz yelesi, yanlarda ve kalçada geriye yatan tutamlar
for _, spot in { { 0.82, 0 }, { 0.72, 1 }, { 0.62, -1 }, { 0.5, 1 }, { 0.38, -1 }, { 0.25, 1 }, { 0.14, -1 } } do
	local s = body.total * spot[1]
	local c = body.at(s)
	local d, n = body.dir(s), dorsalAt(s)
	local side = d:Cross(n).Unit
	for _, sgn in { 1, -1 } do
		local a = rad(40 + 25 * spot[2] + jitter(10))
		local ray = (n * math.cos(a) + side * sgn * math.sin(a)).Unit
		local base = bodySurface(s, ray) - ray * 0.3
		local length = 1.6 * (0.85 + 0.3 * rand())
		tuft("Govde", c.bone, base, -d + ray * 0.35 + V(0, -0.25, 0), ray, length, length * 0.42, C.shade)
	end
end

-- ═════════════════════════════ BAŞ ═════════════════════════════
local skull = ellipsoid("Kafa", "Bas", "bas", HCF(0, 0.2, -0.3), V(2.2, 2.0, 2.4), C.fur, FUR)
local brow = ellipsoid("Alin", "Bas", "bas", HCF(0, 0.62, -1.0), V(1.6, 0.85, 1.5), C.fur, FUR)
local snout = smoothTube("Burun", "Bas", {
	ctl(H(0, 0.05, -1.0), 1.25, 1.05, "bas"),
	ctl(H(0, -0.1, -2.2), 0.85, 0.7, "bas"),
	ctl(H(0, -0.16, -2.95), 0.46, 0.4, "bas"),
}, 0.4, 1.3, C.fur, FUR)
local headParts = { skull, brow }
for _, p in snout do
	table.insert(headParts, p)
end
for _, s in { 1, -1 } do
	table.insert(headParts, ellipsoid("Yanak", "Bas", "bas", HCF(s * 0.76, -0.22, -0.4), V(1.1, 1.15, 1.5), C.fur, FUR))
end
ellipsoid("BurunUcu", "Bas", "bas", HCF(0, -0.06, -3.1), V(0.42, 0.32, 0.36), C.nose, M.SmoothPlastic, { shadow = false })
-- alt çene ve ağız içi
smoothTube("Cene", "Bas", {
	ctl(H(0, -0.6, -0.8), 1.05, 0.55, "cene"),
	ctl(H(0, -0.56, -2.0), 0.7, 0.4, "cene"),
	ctl(H(0, -0.5, -2.65), 0.42, 0.3, "cene"),
}, 0.4, 1.2, C.fur, FUR)
ellipsoid("Agiz", "Bas", "bas", HCF(0, -0.42, -1.6), V(0.7, 0.25, 2.0), C.mouth, M.SmoothPlastic, { shadow = false })
ellipsoid("AgizAlt", "Bas", "cene", HCF(0, -0.5, -1.5), V(0.65, 0.2, 1.8), C.mouth, M.SmoothPlastic, { shadow = false })

local function headSurface(origin, dir)
	return origin + dir * surfaceDistance(headParts, origin, dir)
end
local lids, glowMarks = {}, {}
for _, s in { 1, -1 } do
	-- dudak çizgisi (tilki gülümsemesi)
	segment("Dudak", "Bas", "bas", headSurface(H(0, -0.38, -2.55), HD(s, -0.2, 0).Unit), headSurface(H(0, -0.4, -1.25), HD(s, -0.1, 0).Unit),
		0.08, 0.08, C.black, M.SmoothPlastic, { extend = 1.05, shadow = false, query = false })
	-- mavi göz, dikey göz bebeği, göz kapağı
	local eyeOrigin = H(0, 0.42, -1.2)
	local eyeDir = HD(s * 0.75, 0.2, -0.65).Unit
	local eyePos = headSurface(eyeOrigin, eyeDir) - eyeDir * 0.07
	local eyeLong = HD(s * 0.55, 0.32, 0.75)
	ellipsoid("Goz", "Bas", "bas", lookFrame(eyePos, eyeLong, eyeDir), V(0.36, 0.2, 0.62), C.eye, M.Neon, { shadow = false })
	ellipsoid("GozBebegi", "Bas", "bas", lookFrame(eyePos + eyeDir * 0.07, eyeLong, eyeDir), V(0.3, 0.12, 0.11), C.pupil, M.SmoothPlastic, { shadow = false })
	local lid = ellipsoid("GozKapagi", "Bas", "bas", lookFrame(eyePos + eyeDir * 0.03, eyeLong, eyeDir), V(0.42, 0.24, 0.7), C.fur, FUR,
		{ shadow = false, query = false, transparency = 1 })
	table.insert(lids, lid.Name)
	-- kırmızı işaretler: gözün üstünde kulağa doğru kıvrılan kaş çizgisi ve yanakta iki çizgi
	-- (başın içinden çıkan ışınların yönleri boyunca; ışın yüzeye değdiği yerde çizgi olur)
	local function stroke(from, to, width, steps)
		local points = {}
		local o = H(0, 0.3, -0.9)
		for i = 0, steps do
			local d = HD(lerp(from, to, i / steps).X, lerp(from, to, i / steps).Y, lerp(from, to, i / steps).Z).Unit
			table.insert(points, { pos = headSurface(o, d) - d * 0.03, normal = d, width = width, bone = "bas" })
		end
		ribbon("KirmiziCizgi", "Bas", points, 0.1, C.red, M.SmoothPlastic, 1.9)
	end
	stroke(V(s * 0.3, 0.95, -0.7), V(s * 0.95, 0.75, -0.2), 0.16, 6)
	stroke(V(s * 0.8, -0.02, -0.75), V(s * 1.0, 0.05, -0.12), 0.14, 5)
	stroke(V(s * 0.72, -0.3, -0.75), V(s * 1.0, -0.28, -0.2), 0.12, 5)
	-- yanak tutamları: geriye ve dışa doğru
	for k = 0, 3 do
		local d = HD(s, -0.3 - k * 0.15, 0.3).Unit
		local base = headSurface(H(0, -0.25 - k * 0.12, -0.3 + k * 0.15), d) - d * 0.3
		tuft("Bas", "bas", base, d * 0.6 + HD(0, -0.25, 1), d, 1.5 + k * 0.15, 0.6, if k % 2 == 0 then C.fur else C.shade)
	end
end
-- alındaki mavi işaret: damla biçimli ve altında küçük bir nokta
do
	local d = HD(0, 1, -0.35).Unit
	local pos = headSurface(H(0, 0.5, -1.25), d) - d * 0.03
	table.insert(glowMarks, ellipsoid("AlnIsareti", "Bas", "bas", lookFrame(pos, HD(0, 0.35, 1), d), V(0.32, 0.12, 0.62), C.mark, M.Neon, { shadow = false }).Name)
	local d2 = HD(0, 1, -0.6).Unit
	local pos2 = headSurface(H(0, 0.4, -1.75), d2) - d2 * 0.03
	table.insert(glowMarks, ellipsoid("AlnIsareti", "Bas", "bas", lookFrame(pos2, HD(0, 0.35, 1), d2), V(0.17, 0.1, 0.17), C.mark, M.Neon, { shadow = false }).Name)
end
-- kulaklar: dış kulak beyaz, iç kulak koyu, dibinde kürk
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local bone = "kulak" .. side
	local base = pivotOf(bone)
	local tip = H(s * 1.05, 2.6, 0.15)
	local normal = HD(s * 0.35, 0.05, -1).Unit
	triangle("Kulak", "Bas", bone, base, tip, 1.15, normal, 0.32, C.fur, FUR)
	triangle("IcKulak", "Bas", bone, base + normal * 0.17 + HD(0, 0.15, 0), lerp(base, tip, 0.82) + normal * 0.17, 0.66, normal, 0.08, C.innerEar, M.SmoothPlastic)
	tuft("Bas", bone, base + normal * 0.22 - HD(0, 0.05, 0), HD(s * 0.1, 1, 0.2), normal, 0.7, 0.32, C.fur)
end
-- hale: başın arkasında altın halka ve üzerinde dönen üç parlak boncuk
local haloParts = {}
do
	local u, v = HD(1, 0, 0), HD(0, 1, 0)
	local radius, n = 2.4, 22
	local function at(theta)
		return HALO_CENTER + (u * math.cos(theta) + v * math.sin(theta)) * radius
	end
	for i = 0, n - 1 do
		local p = segment("Hale", "Hale", "hale", at(i / n * math.pi * 2), at((i + 1) / n * math.pi * 2), 0.13, 0.13, C.halo, M.Neon,
			{ extend = 1.12, shadow = false, query = false })
		table.insert(haloParts, p.Name)
	end
	for i = 0, 2 do
		local orb = ellipsoid("HaleBoncugu", "Hale", "hale", CFrame.new(at(i / 3 * math.pi * 2 + 0.4)), V(0.36, 0.36, 0.36), C.haloOrb, M.Neon,
			{ shadow = false, query = false })
		if i == 0 then
			local l = Instance.new("PointLight")
			l.Name = "HaleIsigi"
			l.Color = RGB(255, 226, 160)
			l.Range = 14
			l.Brightness = 1
			l.Shadows = false
			l.Parent = orb
		end
	end
end

-- ═════════════════════════════ KUYRUKLAR ═════════════════════════════
local WIDTHS = { 0.9, 2.0, 2.7, 2.4, 1.2, 0.3 }
local tailTips = {}
for _, tail in tails do
	local P = tail.points
	local group = "Kuyruk" .. tail.k
	local dense = {}
	for i = 1, #P - 1 do
		local p0, p1, p2, p3 = P[math.max(1, i - 1)], P[i], P[i + 1], P[math.min(#P, i + 2)]
		local bone = tail.bones[math.min(i, 4)]
		for k = 0, 3 do
			local t = k / 4
			local w = lerp(WIDTHS[i], WIDTHS[i + 1], t)
			table.insert(dense, ctl(catmull(p0, p1, p2, p3, t), w, w * 0.92, bone))
		end
	end
	table.insert(dense, ctl(P[#P], WIDTHS[#P], WIDTHS[#P], tail.bones[4]))
	local parts, sampler = smoothTube("Kuyruk", group, dense, 0.9, 3.6, C.fur, FUR)
	-- kürk tutamları: iki yanda ve arkada, uca doğru yatık
	local S = V(0, 0, 1):Cross(tail.R).Unit
	for j, u in { 0.3, 0.48, 0.66, 0.82 } do
		local s = sampler.total * u
		local c = sampler.at(s)
		local d = sampler.dir(s)
		for _, ray in { S, -S } do
			ray = (ray + V(0, 0, if j % 2 == 0 then 0.5 else -0.5) - d * (ray + V(0, 0, if j % 2 == 0 then 0.5 else -0.5)):Dot(d)).Unit
			local base = c.pos + ray * (surfaceDistance(parts, c.pos, ray) - 0.45)
			local length = (1.6 + c.w * 0.45) * (0.85 + 0.3 * rand())
			tuft(group, c.bone, base, d + ray * 0.22, ray, length, length * 0.5, if rand() < 0.75 then C.fur else C.shade)
		end
	end
	-- uçta sivri bir tutam
	local tipDir = sampler.dir(sampler.total - 0.3)
	tuft(group, tail.bones[4], P[#P] - tipDir * 0.6, tipDir, V(0, 0, 1):Cross(tipDir).Unit, 1.8, 0.55, C.fur)
	tail.tip = P[#P] - pivotOf(tail.bones[4])
	tailTips[tail.k] = parts[#parts]
end

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
-- Bacak bölümlerinin dinlenme çerçeveleri, oyundaki ters kinematikle aynı işlevlerle hesaplanır.
local rigSource = fs.readFile("src/rig.luau")
local RigCode = luau.load(rigSource, {
	debugName = "rig",
	environment = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, legs = {}, tails = {}, lids = {}, HALO_AXIS = V(0, 0, 1) } },
})()

local legs = {}
for _, def in {
	{ side = 1, front = true }, { side = -1, front = true }, { side = 1, front = false }, { side = -1, front = false },
} do
	local s = def.side
	local hip, knee, ankle, ball, bone, pole
	if def.front then
		hip, knee, ankle, ball = V(s * 1.05, 6.1, -2.2), V(s * 1.2, 3.9, -1.3), V(s * 1.15, 1.5, -2.2), V(s * 1.15, 0.35, -2.7)
		bone, pole = "gogus", V(s * 0.1, 0, 1)
	else
		hip, knee, ankle, ball = V(s * 1.15, 6.3, 2.8), V(s * 1.3, 4.0, 1.6), V(s * 1.25, 2.0, 3.4), V(s * 1.2, 0.35, 2.6)
		bone, pole = "kalca", V(s * 0.1, 0, -1)
	end
	local l1, l2 = (knee - hip).Magnitude, (ankle - knee).Magnitude
	local upperCF, lowerCF = RigCode.legFrames(hip, ankle, pole, l1, l2)
	local frames = { upper = upperCF, lower = lowerCF, meta = RigCode.frame(ankle, ball - ankle, V(0, 0, -1)), foot = CFrame.new(ball) }
	local lm = (ball - ankle).Magnitude
	local group = "Bacak" .. (if def.front then "On" else "Arka") .. (if s > 0 then "L" else "R")
	local leg = { side = s, front = def.front, bone = bone, hip = hip - pivotOf(bone), ball = ball, meta = ankle - ball, l1 = l1, l2 = l2, pole = pole,
		groups = { upper = {}, lower = {}, meta = {}, foot = {} } }
	local function add(key, part)
		table.insert(leg.groups[key], { name = part.Name, offset = frames[key]:Inverse() * part.CFrame })
		return part
	end
	local function piece(key, prefix, localCF, size, color, material)
		return add(key, ellipsoid(prefix, group, nil, frames[key] * localCF, size, color, material or FUR))
	end
	if def.front then
		piece("upper", "Omuz", CFrame.new(0, 0, -l1 * 0.4), V(1.3, 1.5, l1 * 1.35), C.fur)
		piece("lower", "Onkol", CFrame.new(0, 0, -l2 * 0.3), V(0.8, 0.85, l2 * 0.75), C.fur)
		piece("lower", "Corap", CFrame.new(0, 0, -l2 * 0.74), V(0.62, 0.66, l2 * 0.7), C.black)
		add("lower", tuft(group, nil, frames.lower * V(0, 0, -0.2), frames.lower:VectorToWorldSpace(V(0, -0.6, -1)) + V(0, 0, 0.6),
			frames.lower:VectorToWorldSpace(V(0, -1, 0)), 1.2, 0.5, C.shade))
	else
		piece("upper", "Uyluk", CFrame.new(0, 0.12, -l1 * 0.4), V(1.5, 1.9, l1 * 1.4), C.fur)
		piece("lower", "Incik", CFrame.new(0, 0, -l2 * 0.5), V(0.75, 0.8, l2 * 1.1), C.fur)
		piece("lower", "Corap", CFrame.new(0, 0, -l2 * 0.9), V(0.62, 0.66, l2 * 0.45), C.black)
		add("lower", tuft(group, nil, frames.lower * V(0, 0, -l2 * 0.95), frames.lower:VectorToWorldSpace(V(0, 0, -1)) + V(0, 0.2, 0.8),
			frames.lower:VectorToWorldSpace(V(0, -1, 0)), 0.9, 0.4, C.shade))
	end
	piece("meta", "Bilek", CFrame.new(0, 0, -lm * 0.5), V(0.56, 0.6, lm * 1.15), C.black)
	piece("foot", "Pati", CFrame.new(0, -0.05, -0.3), V(0.95, 0.55, 1.15), C.black)
	for i, dx in { -0.33, -0.11, 0.11, 0.33 } do
		piece("foot", "Parmak", CFrame.new(dx, -0.12, -0.85 + math.abs(dx) * 0.4), V(0.26, 0.26, 0.36), C.black)
	end
	table.insert(legs, leg)
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
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Çevrede süzülen ateş böcekleri
for _, part in { bodyParts[math.ceil(#bodyParts / 2)], tailTips[3], tailTips[7] } do
	emitter(part, "AtesBocegi", {
		Texture = SPARKLE, Color = seq({ { 0, RGB(255, 244, 170) }, { 1, RGB(210, 255, 180) } }), LightEmission = 1, LightInfluence = 0,
		Size = nums({ { 0, 0 }, { 0.2, 0.32 }, { 0.8, 0.28 }, { 1, 0 } }), Lifetime = NumberRange.new(6, 9), Rate = 2.5, Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(180, 180), Acceleration = V(0, 0.15, 0), Drag = 0.4, Rotation = NumberRange.new(0, 360),
	})
end
-- Kuyruk uçlarından hafif büyü pırıltısı
for _, part in tailTips do
	emitter(part, "BuyuParilti", {
		Texture = SPARKLE, Color = seq({ { 0, RGB(255, 255, 255) }, { 1, RGB(170, 220, 255) } }), LightEmission = 1, LightInfluence = 0,
		Size = nums({ { 0, 0.25 }, { 1, 0 } }), Lifetime = NumberRange.new(1, 1.6), Rate = 1.5, Speed = NumberRange.new(0.2, 0.8),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
	})
end
-- Tilki ateşleri: ulurken her kuyruğun ucundan çıkıp tilkinin çevresinde dönen mavi alevler
local orbs = {}
for k = 1, 9 do
	local orb = basePart("Part", "TilkiAtesi", "TilkiAtesleri", nil, CFrame.new(TAIL_ROOT), V(0.9, 0.9, 0.9), C.foxfire, M.Neon,
		{ shadow = false, query = false, transparency = 1 })
	orb.Shape = Enum.PartType.Ball
	emitter(orb, "MaviAlev", {
		Texture = FIRE, Color = seq({ { 0, RGB(235, 250, 255) }, { 0.4, RGB(130, 210, 255) }, { 1, RGB(40, 90, 220) } }), LightEmission = 1, LightInfluence = 0,
		Size = nums({ { 0, 1.3 }, { 1, 0.2 } }), Transparency = nums({ { 0, 0.15 }, { 1, 1 } }), Lifetime = NumberRange.new(0.4, 0.7), Rate = 30,
		Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(30, 30), Acceleration = V(0, 3, 0), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90), Enabled = false, attributes = { TilkiAtesi = true },
	})
	local l = Instance.new("PointLight")
	l.Name = "AtesIsigi"
	l.Color = RGB(130, 200, 255)
	l.Range = 10
	l.Brightness = 0
	l.Shadows = false
	l.Parent = orb
	table.insert(orbs, orb.Name)
end

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

local function collider(name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Parent = folder("Carpisma")
end
collider("GovdeCarpisma", CFrame.new(0, 6.8, 0.3), V(3.2, 3.8, 7.6))
collider("BacakCarpisma", CFrame.new(0, 2.6, 0.1), V(3.4, 5.2, 6.6))
collider("BasCarpisma", CFrame.new(0, 9.0, -4.8), V(2.6, 3.4, 3.2))

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
local function quoteAll(list)
	local out = {}
	for _, n in list do
		table.insert(out, string.format("%q", n))
	end
	return table.concat(out, ", ")
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
table.insert(lines, "")
-- Bacaklar: kök kemiğe göre, pati ve bilek model uzayında; parçalar bacak bölümlerine göre.
table.insert(lines, "Rig.legs = {")
for _, leg in legs do
	table.insert(lines, string.format("\t{ side = %d, front = %s, bone = %d, hip = %s, ball = %s, meta = %s, l1 = %s, l2 = %s, pole = %s, groups = {",
		leg.side, tostring(leg.front), boneIndex[leg.bone], v3(leg.hip), v3(leg.ball), v3(leg.meta), fmt(leg.l1), fmt(leg.l2), v3(leg.pole)))
	for _, key in { "upper", "lower", "meta", "foot" } do
		local out = {}
		for _, p in leg.groups[key] do
			table.insert(out, string.format("{ name = %q, offset = %s }", p.name, cfLiteral(p.offset)))
		end
		table.insert(lines, string.format("\t\t%s = { %s },", key, table.concat(out, ", ")))
	end
	table.insert(lines, "\t} },")
end
table.insert(lines, "}")
table.insert(lines, "")
-- Kuyruklar: kemikler kökten uca; fan = yelpaze ekseni (pozitif açı dışa açar), lift = geriye yatırma ekseni.
table.insert(lines, "Rig.tails = {")
for _, tail in tails do
	local idx = {}
	for _, name in tail.bones do
		table.insert(idx, tostring(boneIndex[name]))
	end
	table.insert(lines, string.format("\t{ bones = { %s }, side = %d, phase = %s, fan = %s, lift = %s, tip = %s },",
		table.concat(idx, ", "), tail.side, fmt(tail.phase), v3(tail.fan), v3(tail.lift), v3(tail.tip)))
end
table.insert(lines, "}")
table.insert(lines, "Rig.HALO_AXIS = " .. v3(HALO_AXIS))
table.insert(lines, "Rig.lids = { " .. quoteAll(lids) .. " }")
table.insert(lines, "Rig.marks = { " .. quoteAll(glowMarks) .. " }")
table.insert(lines, "Rig.halo = { " .. quoteAll(haloParts) .. " }")
table.insert(lines, "Rig.orbs = { " .. quoteAll(orbs) .. " }")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "TilkiRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("DokuzKuyrukluTilki.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("DokuzKuyrukluTilki.rbxmx yazıldı: %d parça, %d kemik", count, #bones))
for name, f in folders do
	print(string.format("  %-16s %d", name, #f:GetChildren()))
end
