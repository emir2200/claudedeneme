--[[
	Lav Golemi modelini üretir: lune run src/build.luau   (golem/ klasöründen)
	Çıktı: LavGolemi.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Golemin her uzvu bir kaya kütlesidir: üst üste binen bazalt elipslerden pürüzsüz bir gövde,
	yüzeyinde dallanan parlak lav çatlakları ve yüzeye yarı gömülü köşeli kaya parçaları.
	Gövde, baş ve kollar kemiklere; bacak parçaları bacak bölümlerine bağlıdır ve
	"GolemRig" ModuleScript'ine veri olarak yazılır.
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
local seed = 9090909
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (kömür karası bazalt, turuncu lav, sarı gözler) ───
local RGB = Color3.fromRGB
local ROCKS = { RGB(46, 44, 48), RGB(56, 54, 58), RGB(40, 40, 44), RGB(64, 60, 62) }
local C = {
	lava = RGB(255, 110, 20),
	eye = RGB(255, 170, 40),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "LavGolemi"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 14)
model:SetAttribute("AnimasyonHizi", 1)
model:SetAttribute("KameraSarsintisi", true)

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

-- Lav nabzı göğüsteki "kalpten" dışa doğru yayılır: her parlayan parçanın gecikmesi (sn).
local HEART = V(0, 9.6, -0.5)

-- ─── Parça yardımcıları ───
local rigParts = {} -- { name, bone, cf }
local glowParts = {} -- { name, phase }
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
	p.Material = material or M.Basalt
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	p.Parent = folder(group)
	if bone then
		table.insert(rigParts, { name = p.Name, bone = bone, cf = cf })
	end
	if opts.glow then
		table.insert(glowParts, { name = p.Name, phase = (cf.Position - HEART).Magnitude * 0.05 })
	end
	if opts.register then
		opts.register(p)
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

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function ctl(pos, w, h, bone)
	return { pos = pos, w = w, h = h, bone = bone }
end

local function pickRock()
	return ROCKS[1 + math.floor(rand() * #ROCKS)]
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
	return { at = at, total = total }
end

--- Zincirin `s` noktasındaki yönü ve eksene dik iki birim vektör.
local function chainFrame(sampler, s)
	local dir = (sampler.at(s + 0.3).pos - sampler.at(s - 0.3).pos).Unit
	local ref = if math.abs(dir.X) < 0.9 then V(1, 0, 0) else V(0, 0, 1)
	local side = (ref - dir * ref:Dot(dir)).Unit
	return dir, side, dir:Cross(side).Unit
end

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir kaya kütlesi.
local function smoothTube(prefix, group, controls, spacing, length, opts)
	local sampler = chainSampler(controls)
	local half = math.min(length, sampler.total) / 2
	local span = sampler.total - 2 * half
	local count = math.max(1, math.ceil(span / spacing) + 1)
	local made = {}
	for j = 0, count - 1 do
		local s = half + (if count > 1 then span * j / (count - 1) else span / 2)
		local c = sampler.at(s)
		local look = sampler.at(s + half * 0.5).pos - sampler.at(s - half * 0.5).pos
		table.insert(made, ellipsoid(prefix, group, c.bone, lookFrame(c.pos, look), V(c.w, c.h, half * 2), ROCKS[2], M.Basalt, { register = opts.register }))
	end
	return made, sampler
end

--- `origin`dan `dir` yönünde giden ışının elips parçalardan en dışta çıktığı mesafe (yüzey).
local function surfaceDistance(parts, origin, dir)
	local best = 0
	for _, p in parts do
		local r = p.Size / 2
		local o = p.CFrame:PointToObjectSpace(origin) / r
		local d = p.CFrame:VectorToObjectSpace(dir) / r
		local a, b, c = d:Dot(d), 2 * o:Dot(d), o:Dot(o) - 1
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			best = math.max(best, (-b + math.sqrt(disc)) / (2 * a))
		end
	end
	return best
end

--- Kayanın yüzeyine lav çatlağı ağı çizer. Yüzey (yay uzunluğu s, çevre açısı φ) ile
--- parametrelenir; titretilmiş bir ızgaranın üçgenlerinin ağırlık merkezleri komşu üçgenlerle
--- birleştirilir. Ortaya düzensiz çokgen kaya parçaları ve aralarında parlayan lav çıkar.
local function crackNet(group, surfaceParts, sampler, opts)
	local sFrom, sTo = opts.from or 0, opts.to or sampler.total
	local cell = opts.cell or 2.2
	local radius = 0
	for k = 0, 8 do
		local c = sampler.at(lerp(sFrom, sTo, k / 8))
		radius += (c.w + c.h) / 4 / 9
	end
	local nu = math.max(1, math.floor((sTo - sFrom) / cell + 0.5))
	local nv = math.max(3, math.floor(math.pi * 2 * radius / cell + 0.5))
	local verts = {}
	for i = 0, nu do
		verts[i] = {}
		for j = 0, nv - 1 do
			verts[i][j] = { u = i + (if i > 0 and i < nu then jitter(0.35) else 0), v = j + jitter(0.35) }
		end
	end
	local function corner(i, j)
		local jj = j % nv
		local p = verts[i][jj]
		return i * 1000 + jj, p.u, p.v + (j - jj)
	end
	local centroids, edgeTris, edgeOrder = {}, {}, {}
	local function tri(a, b, c)
		local ka, ua, va = corner(a[1], a[2])
		local kb, ub, vb = corner(b[1], b[2])
		local kc, uc, vc = corner(c[1], c[2])
		table.insert(centroids, { u = (ua + ub + uc) / 3, v = (va + vb + vc) / 3 })
		for _, e in { { ka, kb }, { kb, kc }, { kc, ka } } do
			local key = math.min(e[1], e[2]) .. ":" .. math.max(e[1], e[2])
			if not edgeTris[key] then
				edgeTris[key] = {}
				table.insert(edgeOrder, key)
			end
			table.insert(edgeTris[key], #centroids)
		end
	end
	for i = 0, nu - 1 do
		for j = 0, nv - 1 do
			local a, b, c, d = { i, j }, { i + 1, j }, { i, j + 1 }, { i + 1, j + 1 }
			if rand() < 0.5 then
				tri(a, b, d)
				tri(a, d, c)
			else
				tri(a, b, c)
				tri(b, d, c)
			end
		end
	end
	local function surfacePoint(u, v)
		local s = lerp(sFrom, sTo, u / nu)
		local phi = v / nv * math.pi * 2
		local _, side, normal = chainFrame(sampler, s)
		local ray = side * math.cos(phi) + normal * math.sin(phi)
		local origin = sampler.at(s).pos
		local d = surfaceDistance(surfaceParts, origin, ray)
		return origin + ray * d, ray, d
	end
	local count = 0
	for _, key in edgeOrder do
		local pair = edgeTris[key]
		if #pair == 2 and rand() >= (opts.drop or 0.15) then
			local a, b = centroids[pair[1]], centroids[pair[2]]
			local pa, ra, da = surfacePoint(a.u, a.v)
			local pb, rb, db = surfacePoint(b.u, b.v)
			local len = (pb - pa).Magnitude
			if da > 0 and db > 0 and len > 0.25 then
				local normal = (ra + rb).Unit
				local bone = sampler.at(lerp(sFrom, sTo, (a.u + b.u) / 2 / nu)).bone
				local width = (opts.width or 0.34) * (0.55 + 0.9 * rand())
				ellipsoid("Catlak", group, bone, lookFrame((pa + pb) / 2 + normal * 0.04, pb - pa, normal), V(width, 0.42, len * 1.3), C.lava, M.Neon,
					{ glow = true, shadow = false, query = false, register = opts.register })
				count += 1
			end
		end
	end
	return count
end

--- Yüzeye yarı gömülü köşeli kaya parçaları: golemin pürüzlü, kayalık siluetini verir.
local function chunks(prefix, group, surfaceParts, sampler, count, size, opts)
	for _ = 1, count do
		local s = sampler.total * (0.12 + 0.76 * rand())
		local c = sampler.at(s)
		local _, side, normal = chainFrame(sampler, s)
		local phi = rand() * math.pi * 2
		local ray = side * math.cos(phi) + normal * math.sin(phi)
		local pos = c.pos + ray * surfaceDistance(surfaceParts, c.pos, ray)
		local sz = V(size * (0.8 + 0.6 * rand()), size * (0.32 + 0.22 * rand()), size * (0.8 + 0.6 * rand()))
		local cf = lookFrame(pos - ray * sz.Y * 0.18, ray:Cross(V(rand() - 0.5, rand() - 0.5, rand() - 0.5)), ray)
			* CFrame.Angles(jitter(0.22), jitter(0.6), jitter(0.22))
		basePart("Part", prefix, group, c.bone, cf, sz, pickRock(), if rand() < 0.7 then M.Basalt else M.Slate, { register = opts.register })
	end
end

local crackCount = 0
--- Bir kaya uzvu: bazalt kütle, üstünde lav çatlakları ve yarı gömülü kaya parçaları.
local function rock(prefix, group, controls, opts)
	opts = opts or {}
	if opts.extendEnds then
		local first, last = controls[1], controls[#controls]
		local d0 = (controls[2].pos - first.pos).Unit
		local d1 = (last.pos - controls[#controls - 1].pos).Unit
		controls = table.clone(controls)
		controls[1] = ctl(first.pos - d0 * opts.extendEnds, first.w * 0.92, first.h * 0.92, first.bone)
		controls[#controls] = ctl(last.pos + d1 * opts.extendEnds, last.w * 0.92, last.h * 0.92, last.bone)
	end
	local parts, sampler = smoothTube(prefix, group, controls, opts.spacing or 0.8, opts.length or 3.2, opts)
	crackCount += crackNet(group, parts, sampler, { cell = opts.cell, width = opts.crackWidth, drop = opts.drop, from = opts.from, to = opts.to,
		register = opts.register })
	chunks(prefix .. "Tas", group, parts, sampler, opts.chunks or 5, opts.chunkSize or 1.4, opts)
	return parts, sampler
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("kok", nil, V(0, 5.4, 0.4))
addBone("govde", "kok", V(0, 7.2, 0.3))
addBone("bas", "govde", V(0, 12.0, -0.6))
local ARMS = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	ARMS[side] = { s = s, shoulder = V(s * 4.6, 10.9, 0.1), elbow = V(s * 5.3, 7.6, 0.5), wrist = V(s * 5.5, 4.8, -0.4) }
	addBone("kol" .. side, "govde", ARMS[side].shoulder)
	addBone("onkol" .. side, "kol" .. side, ARMS[side].elbow)
	addBone("yumruk" .. side, "onkol" .. side, ARMS[side].wrist)
end

-- ═════════════════════════════ GÖVDE VE BAŞ ═════════════════════════════
-- kalçadan boyna dikey uzanan, göğüste genişleyen iri kaya gövde
local chestParts = rock("Govde", "Govde", {
	ctl(V(0, 4.5, 0.4), 4.4, 3.4, "kok"),
	ctl(V(0, 5.6, 0.35), 5.2, 4.0, "kok"),
	ctl(V(0, 7.0, 0.3), 5.6, 4.3, "govde"),
	ctl(V(0, 8.8, 0.1), 7.2, 5.0, "govde"),
	ctl(V(0, 10.5, 0.0), 8.0, 5.4, "govde"),
	ctl(V(0, 12.0, 0.15), 7.0, 4.6, "govde"),
	ctl(V(0, 12.8, 0.3), 4.6, 3.2, "govde"),
}, { cell = 2.3, crackWidth = 0.42, chunks = 12, chunkSize = 2.2, spacing = 0.8, length = 4.4 })
local chestCore = chestParts[math.ceil(#chestParts * 0.6)]
-- omuzlar: iri kaya yumruları
local shoulderParts = {}
for _, s in { 1, -1 } do
	local parts = rock("Omuz", "Govde", { ctl(V(s * 3.0, 11.7, 0.15), 3.6, 3.6, "govde"), ctl(V(s * 5.3, 11.3, 0.15), 3.3, 3.3, "govde") },
		{ cell = 2.0, chunks = 5, chunkSize = 1.5, spacing = 0.8, length = 2.6 })
	table.insert(shoulderParts, parts[#parts])
end
-- sırtta birkaç çıkıntılı kaya
for _, p in { V(0, 11.0, 2.4), V(-1.8, 9.4, 2.5), V(1.7, 10.0, 2.5), V(0.5, 7.8, 2.3) } do
	basePart("Part", "Sirt", "Govde", "govde", CFrame.new(p) * CFrame.Angles(jitter(0.5), jitter(0.8), jitter(0.5)), V(1.6, 1.3, 1.2) * (0.9 + 0.3 * rand()), pickRock(), M.Basalt)
end
-- baş: omuzların arasına gömülü küçük bir kaya; altın sarısı gözler, üstlerinde kaş taşı
local headCF = CFrame.new(0, 12.9, -0.8)
rock("Kafa", "Bas", { ctl(V(0, 12.0, -0.7), 2.5, 2.5, "bas"), ctl(V(0, 13.9, -0.9), 2.3, 2.4, "bas") },
	{ cell = 1.6, crackWidth = 0.22, chunks = 3, chunkSize = 0.9, spacing = 0.6, length = 2.2, drop = 0.3 })
local eyes = {}
for _, s in { 1, -1 } do
	local eye = basePart("Part", "Goz", "Bas", "bas", headCF * CFrame.new(s * 0.46, 0.12, -1.18) * CFrame.Angles(0, s * rad(-12), s * rad(-14)), V(0.56, 0.2, 0.3), C.eye, M.Neon,
		{ shadow = false })
	table.insert(eyes, eye.Name)
end
basePart("Part", "Kas", "Bas", "bas", headCF * CFrame.new(0, 0.5, -1.05) * CFrame.Angles(rad(-18), 0, 0), V(1.9, 0.45, 0.8), ROCKS[3], M.Basalt)
basePart("Part", "Cene", "Bas", "bas", headCF * CFrame.new(0, -0.75, -0.85) * CFrame.Angles(rad(12), 0, 0), V(1.5, 0.7, 0.8), ROCKS[2], M.Basalt)

-- ═════════════════════════════ KOLLAR ═════════════════════════════
local fistParts = {}
for _, side in { "L", "R" } do
	local arm = ARMS[side]
	local s = arm.s
	local kol, onkol, yumruk = "kol" .. side, "onkol" .. side, "yumruk" .. side
	local group = "Kol" .. side
	rock("Kol", group, { ctl(arm.shoulder, 2.8, 2.8, kol), ctl(arm.elbow, 2.5, 2.5, kol) }, { cell = 2.1, chunks = 3, chunkSize = 1.6, spacing = 0.7, length = 3.4, extendEnds = 0.7 })
	rock("Onkol", group, { ctl(arm.elbow, 2.5, 2.5, onkol), ctl(arm.wrist, 3.0, 3.0, onkol) }, { cell = 2.1, chunks = 3, chunkSize = 1.6, spacing = 0.7, length = 3.4, extendEnds = 0.7 })
	-- dev yumruk ve önünde parmak boğumları
	local fist = arm.wrist + V(s * 0.1, -1.0, -0.35)
	local parts = rock("Yumruk", group, { ctl(arm.wrist + V(0, 0.2, 0), 3.0, 3.0, yumruk), ctl(fist + V(0, -0.8, -0.2), 3.1, 3.2, yumruk) },
		{ cell = 1.9, chunks = 3, chunkSize = 1.4, spacing = 0.7, length = 2.6, extendEnds = 0.3 })
	fistParts[side] = parts[#parts]
	for i = -1, 1 do
		basePart("Part", "Bogum", group, yumruk, CFrame.new(fist + V(i * 0.78, -0.2 + jitter(0.15), -1.45)) * CFrame.Angles(jitter(0.3), jitter(0.3), jitter(0.3)),
			V(0.8, 0.85, 0.75), pickRock(), M.Basalt)
	end
end

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
-- Bacak bölümlerinin dinlenme çerçeveleri, oyundaki ters kinematikle aynı işlevlerle hesaplanır.
local rigSource = fs.readFile("src/rig.luau")
local RigCode = luau.load(rigSource, {
	debugName = "rig",
	environment = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, legs = {}, glowGroups = {}, eyes = {} } },
})()

local legs = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local hip, knee, ankle, ball = V(s * 1.9, 5.2, 0.4), V(s * 2.5, 3.1, -1.2), V(s * 2.6, 1.0, 0.2), V(s * 2.7, 0.8, -0.3)
	local l1, l2 = (knee - hip).Magnitude, (ankle - knee).Magnitude
	local pole = V(s * 0.3, 0, -1)
	local upperCF, lowerCF = RigCode.legFrames(hip, ankle, pole, l1, l2)
	local frames = { upper = upperCF, lower = lowerCF, foot = CFrame.new(ball) }
	local group = "Bacak" .. side
	local leg = { side = s, hip = hip - pivotOf("kok"), ankle = ankle, ball = ball, l1 = l1, l2 = l2, pole = pole, groups = { upper = {}, lower = {}, foot = {} } }
	local function registerFor(key)
		return function(part)
			table.insert(leg.groups[key], { name = part.Name, offset = frames[key]:Inverse() * part.CFrame })
		end
	end
	rock("Uyluk", group, { ctl(hip + V(0, 0.3, 0), 3.1, 3.1, nil), ctl(knee, 2.7, 2.7, nil) },
		{ register = registerFor("upper"), cell = 2.1, chunks = 3, chunkSize = 1.6, spacing = 0.7, length = 3.2, extendEnds = 0.7 })
	rock("Baldir", group, { ctl(knee, 2.7, 2.7, nil), ctl(ankle, 2.5, 2.5, nil) },
		{ register = registerFor("lower"), cell = 2.1, chunks = 3, chunkSize = 1.6, spacing = 0.7, length = 3.0, extendEnds = 0.6 })
	-- iri kaya ayak ve önünde parmak kayaları
	rock("Ayak", group, { ctl(ball + V(0, 0.05, 1.3), 3.0, 1.6, nil), ctl(ball + V(0, 0, -1.4), 3.2, 1.5, nil) },
		{ register = registerFor("foot"), cell = 1.9, chunks = 3, chunkSize = 1.5, spacing = 0.8, length = 2.6, drop = 0.3 })
	for i = -1, 1 do
		basePart("Part", "AyakParmagi", group, nil, CFrame.new(ball + V(i * 0.95, -0.25, -2.1 + math.abs(i) * 0.3)) * CFrame.Angles(jitter(0.3), jitter(0.4), jitter(0.3)),
			V(0.95, 0.8, 0.95), pickRock(), M.Basalt, { register = registerFor("foot") })
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
local function attachment(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local EMBER = seq({ { 0, RGB(255, 220, 110) }, { 1, RGB(255, 80, 10) } })

-- göğüs: kor ve ışık
emitter(chestCore, "Kivilcim", {
	Texture = SPARKLE, Color = EMBER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.35 }, { 1, 0 } }),
	Lifetime = NumberRange.new(1.6, 2.6), Rate = 8, Speed = NumberRange.new(1.5, 3.5), SpreadAngle = Vector2.new(180, 180),
	Acceleration = V(0, 4, 0), Rotation = NumberRange.new(0, 360),
})
local light = Instance.new("PointLight")
light.Name = "GogusIsigi"
light.Color = RGB(255, 120, 30)
light.Range = 18
light.Brightness = 1.5
light.Shadows = false
light.Parent = chestCore
-- omuzlardan yükselen ince duman
for _, part in shoulderParts do
	emitter(part, "Duman", {
		Texture = SMOKE, Color = seq({ { 0, RGB(70, 60, 56) }, { 1, RGB(30, 28, 28) } }), LightInfluence = 0.6,
		Size = nums({ { 0, 1 }, { 1, 4 } }), Transparency = nums({ { 0, 0.55 }, { 1, 1 } }), Lifetime = NumberRange.new(2.5, 3.5),
		Rate = 3, Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(15, 15), Acceleration = V(0, 1.5, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20), EmissionDirection = Enum.NormalId.Top,
	})
end
-- yumruklardan damlayan lav
for _, part in fistParts do
	emitter(part, "LavDamlasi", {
		Texture = FIRE, Color = EMBER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.5 }, { 1, 0.3 } }),
		Lifetime = NumberRange.new(0.6, 0.8), Rate = 1.5, Speed = NumberRange.new(0, 0.5), Acceleration = V(0, -40, 0),
		EmissionDirection = Enum.NormalId.Bottom,
	})
end

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

-- yere vurunca: toz, lav sıçraması ve kaya parçaları (animasyon script'i bir kez saçar)
local impact = attachment(root, "VurusNoktasi", CFrame.new(0, 0.3, -4.8))
emitter(impact, "Toz", {
	Texture = SMOKE, Color = seq({ { 0, RGB(110, 100, 92) }, { 1, RGB(60, 56, 54) } }), LightInfluence = 0.8,
	Size = nums({ { 0, 2 }, { 1, 8 } }), Transparency = nums({ { 0, 0.35 }, { 1, 1 } }), Lifetime = NumberRange.new(1.4, 2.4), Rate = 0,
	Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(85, 15), Drag = 2.5, Acceleration = V(0, 2, 0),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), EmissionDirection = Enum.NormalId.Top,
	attributes = { VurusEfekti = true, Adet = 50 },
})
emitter(impact, "LavSicramasi", {
	Texture = FIRE, Color = EMBER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.9 }, { 1, 0.4 } }),
	Lifetime = NumberRange.new(0.9, 1.4), Rate = 0, Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(40, 40),
	Acceleration = V(0, -45, 0), Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top,
	attributes = { VurusEfekti = true, Adet = 40 },
})
emitter(impact, "TasParcasi", {
	Texture = SMOKE, Color = seq({ { 0, RGB(40, 38, 40) }, { 1, RGB(30, 30, 32) } }), LightInfluence = 1,
	Size = nums({ { 0, 0.6 }, { 1, 0.5 } }), Lifetime = NumberRange.new(1.0, 1.5), Rate = 0, Speed = NumberRange.new(16, 28),
	SpreadAngle = Vector2.new(55, 55), Acceleration = V(0, -50, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
	EmissionDirection = Enum.NormalId.Top, attributes = { VurusEfekti = true, Adet = 30 },
})
-- şok dalgası halkası: yerde genişleyen, sönen bir lav halkası
local ring = basePart("Part", "SokDalgasi", "Efektler", nil, CFrame.new(0, 0.12, -4.8) * CFrame.Angles(0, 0, math.pi / 2), V(0.15, 4, 4), C.lava, M.Neon,
	{ shadow = false, query = false, transparency = 1 })
ring.Shape = Enum.PartType.Cylinder

-- ═════════════════════════════ ÇARPIŞMA ═════════════════════════════
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
collider("GovdeCarpisma", CFrame.new(0, 9.4, 0.2), V(9.6, 7.6, 5.8))
collider("BacakCarpisma", CFrame.new(0, 2.8, -0.2), V(7.2, 5.6, 4.6))

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
-- Bacaklar: kalça kök kemiğe göre, bilek ve ayak model uzayında; parçalar bacak bölümlerine göre.
table.insert(lines, "Rig.legs = {")
for _, leg in legs do
	table.insert(lines, string.format("\t{ side = %d, bone = %d, hip = %s, ankle = %s, ball = %s, l1 = %s, l2 = %s, pole = %s, groups = {",
		leg.side, boneIndex.kok, v3(leg.hip), v3(leg.ankle), v3(leg.ball), fmt(leg.l1), fmt(leg.l2), v3(leg.pole)))
	for _, key in { "upper", "lower", "foot" } do
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
-- Lav çekirdekleri nabız gecikmesine göre gruplanır (0.2 sn'lik dilimler).
local groups, groupList = {}, {}
for _, g in glowParts do
	local key = math.floor(g.phase / 0.2 + 0.5)
	if not groups[key] then
		groups[key] = {}
		table.insert(groupList, key)
	end
	table.insert(groups[key], string.format("%q", g.name))
end
table.sort(groupList)
table.insert(lines, "Rig.glowGroups = {")
for _, key in groupList do
	table.insert(lines, string.format("\t{ phase = %s, parts = { %s } },", fmt(key * 0.2), table.concat(groups[key], ", ")))
end
table.insert(lines, "}")
table.insert(lines, "Rig.eyes = { " .. quoteAll(eyes) .. " }")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "GolemRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("LavGolemi.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("LavGolemi.rbxmx yazıldı: %d parça (%d lav çatlağı), %d kemik, %d parıltı grubu", count, crackCount, #bones, #groupList))
for name, f in folders do
	print(string.format("  %-10s %d", name, #f:GetChildren()))
end
