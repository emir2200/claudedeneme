--[[
	Buz Yılanı modelini üretir: lune run src/build.luau   (buzyilani/ klasöründen)
	Çıktı: BuzYilani.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Yılanın gövdesi tek bir eğri boyunca uzanır: kuyruk ucundan başlayıp yerde bir buçuk tur
	kıvrılır, sonra halkanın arkasından yükselip kemer çizerek öne eğilen boynuna ve başına ulaşır.
	Eğri boyunca her 4.5 stud'da bir kemik vardır; parçaların kemiğe göre konumları
	"YilanRig" ModuleScript'ine veri olarak yazılır.
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
local seed = 4040404
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (görseldeki lavanta-mavi pullar, beyaz lekeler, buz tüyleri, mor gözler) ───
local RGB = Color3.fromRGB
local C = {
	scale = RGB(146, 154, 212),
	scaleDark = RGB(108, 114, 186),
	patch = RGB(232, 240, 252),
	belly = RGB(200, 196, 224),
	seam = RGB(150, 144, 190),
	feathers = { RGB(238, 245, 255), RGB(210, 226, 252), RGB(226, 224, 250), RGB(246, 250, 255) },
	eye = RGB(214, 170, 255),
	pupil = RGB(40, 20, 70),
	mouth = RGB(112, 64, 108),
	mouthLow = RGB(132, 82, 126),
	fang = RGB(240, 244, 255),
	tongue = RGB(62, 78, 160),
	nostril = RGB(60, 60, 110),
	crystal = RGB(190, 225, 255),
	snow = RGB(244, 248, 255),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "BuzYilani"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 14)
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
	p.Material = material or M.Slate
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

--- Diş/diken: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
local function spike(prefix, group, bone, pos, out, back, height, length, thickness, color, material, opts)
	out = out.Unit
	back = (back - out * back:Dot(out)).Unit
	local right = out:Cross(back).Unit
	local cf = CFrame.fromMatrix(pos + out * (height / 2), right, out, back)
	return basePart("WedgePart", prefix, group, bone, cf, V(thickness, height, length), color, material or M.SmoothPlastic, opts)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

--- Kontrol noktaları ({ pos, w, h, bone }) boyunca `step` aralıklı örnekler.
local function sampleChain(controls, step)
	local samples = {}
	for i = 1, #controls - 1 do
		local c0, c1 = controls[i], controls[i + 1]
		local seg = c1.pos - c0.pos
		local n = math.max(1, math.ceil(seg.Magnitude / step))
		for k = 0, n - 1 do
			local t = k / n
			table.insert(samples, {
				pos = c0.pos + seg * t,
				w = lerp(c0.w, c1.w, t),
				h = lerp(c0.h, c1.h, t),
				bone = if t < 0.5 then c0.bone else c1.bone,
			})
		end
	end
	local last = controls[#controls]
	table.insert(samples, { pos = last.pos, w = last.w, h = last.h, bone = last.bone })
	return samples
end

--- Zinciri yay uzunluğuyla örnekler: sampler.at(s) → { pos, w, h, bone }, sampler.total.
local function chainSampler(controls)
	local samples = sampleChain(controls, 0.25)
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

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir boru. `spacing` elips
--- merkezleri arası, `length` her elipsin boyu; length/spacing ≥ 3 iken halka izi kalmaz.
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
	return made
end

--- `origin`dan `dir` yönünde giden ışının elips parçalardan en dışta çıktığı mesafe (yüzey).
--- Yalnızca `origin`ı içine alan elipslere bakılır; yılan kıvrıldığı için ışın gövdenin başka
--- bir kıvrımına da çarpabilir, o çarpışmalar yüzey sayılmaz. İçine alan elips yoksa en yakın
--- `maxDist` içindeki çıkış kullanılır.
local function surfaceDistance(parts, origin, dir, maxDist: number?)
	local inside, near = 0, 0
	for _, p in parts do
		local r = p.Size / 2
		local o = p.CFrame:PointToObjectSpace(origin) / r
		local d = p.CFrame:VectorToObjectSpace(dir) / r
		local a, b, c = d:Dot(d), 2 * o:Dot(d), o:Dot(o) - 1
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			local exit = (-b + math.sqrt(disc)) / (2 * a)
			if c < 0 then
				inside = math.max(inside, exit)
			elseif exit <= (maxDist or 4) then
				near = math.max(near, exit)
			end
		end
	end
	return if inside > 0 then inside else near
end

--- Catmull-Rom ile yumuşatılmış eğri noktaları.
local function smoothCurve(points, perSegment)
	local out = {}
	local n = #points
	for i = 1, n - 1 do
		local p0 = points[math.max(1, i - 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(n, i + 2)]
		for k = 0, perSegment - 1 do
			local t = k / perSegment
			local t2, t3 = t * t, t * t * t
			table.insert(out, (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
		end
	end
	table.insert(out, points[n])
	return out
end

--- Parçalı doğrusal profil: points = { {s, değer}, ... }.
local function profile(points)
	return function(s)
		if s <= points[1][1] then
			return points[1][2]
		end
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if s <= b[1] then
				return lerp(a[2], b[2], (s - a[1]) / (b[1] - a[1]))
			end
		end
		return points[#points][2]
	end
end

--- Buz tüyü: yassı, yaprak biçimli bir elips. Tabanı `base`, `dir` yönünde uzanır; düz yüzü `normal`e bakar.
local function feather(group, bone, base, dir, normal, length, width, color)
	dir = dir.Unit
	return ellipsoid("Tuy", group, bone, lookFrame(base + dir * (length * 0.45), dir, normal), V(width, 0.2, length),
		color or C.feathers[1 + math.floor(rand() * #C.feathers)], M.Ice, { query = false })
end

-- ═════════════════════════════ GÖVDE EĞRİSİ ═════════════════════════════
-- Yerdeki sarmal: kuyruk ucu dışarıda, gövde içe doğru bir buçuk tur kıvrılıp halkanın arkasında biter.
local SPIRAL_POINTS = 14
local spiral = {}
for k = 0, SPIRAL_POINTS - 1 do
	local theta = math.pi / 3 + k * math.pi / 6
	local r = 13 - 5 * k / (SPIRAL_POINTS - 1)
	table.insert(spiral, V(r * math.cos(theta), 0, r * math.sin(theta)))
end
-- Halkanın arkasından yükselen, kemer çizip öne eğilen boyun; son nokta başın pivotu.
local NECK = {
	{ V(-2.6, 3.6, 7.4), V(0, 1, 0.3) },
	{ V(-3.4, 6.6, 5.9), V(0.2, 0.3, 1) },
	{ V(-3.0, 10.4, 4.5), V(0.1, 0, 1) },
	{ V(-2.0, 14.4, 3.7), V(0, 0, 1) },
	{ V(-0.8, 18.2, 3.2), V(0, 0.2, 1) },
	{ V(0.2, 21.4, 2.0), V(0, 0.8, 1) },
	{ V(0.6, 23.2, -0.6), V(0, 1, 0.2) },
	{ V(0.4, 22.8, -3.6), V(0, 1, -0.3) },
	{ V(0, 21.0, -6.0), V(0, 0.8, -0.6) },
	{ V(-0.3, 18.6, -7.8), V(0, 0.9, -0.42) },
}
local PER = 6
local curve, arcs, controlArc
local function buildCurve(heights)
	local points = {}
	for k, p in spiral do
		table.insert(points, V(p.X, heights[k], p.Z))
	end
	for _, n in NECK do
		table.insert(points, n[1])
	end
	curve = smoothCurve(points, PER)
	arcs = { 0 }
	for i = 2, #curve do
		arcs[i] = arcs[i - 1] + (curve[i] - curve[i - 1]).Magnitude
	end
	controlArc = {}
	for i = 1, #points do
		controlArc[i] = arcs[(i - 1) * PER + 1]
	end
end
-- Önce yaklaşık yüksekliklerle eğriyi kur, sonra sarmalı gövde kalınlığına göre yere oturt.
local initial = {}
for k = 1, SPIRAL_POINTS do
	initial[k] = 2.4
end
buildCurve(initial)
local TOTAL = arcs[#arcs]
local S_RISE = controlArc[SPIRAL_POINTS]
local widthAt = profile({
	{ 0, 0.5 }, { 12, 3.0 }, { 30, 4.8 }, { S_RISE * 0.8, 5.4 }, { S_RISE, 5.2 },
	{ S_RISE + (TOTAL - S_RISE) * 0.45, 4.2 }, { TOTAL - 3, 3.4 }, { TOTAL, 3.0 },
})
local heights = {}
for k = 1, SPIRAL_POINTS do
	heights[k] = 0.46 * widthAt(controlArc[k])
end
buildCurve(heights)
TOTAL = arcs[#arcs]
S_RISE = controlArc[SPIRAL_POINTS]

local function curveAt(s)
	s = math.clamp(s, 0, TOTAL)
	local i = 1
	while i < #curve - 1 and arcs[i + 1] < s do
		i += 1
	end
	local t = (s - arcs[i]) / math.max(1e-6, arcs[i + 1] - arcs[i])
	return lerp(curve[i], curve[i + 1], t)
end
local function dirAt(s)
	return (curveAt(s + 0.5) - curveAt(s - 0.5)).Unit
end
-- Sırt yönü: sarmalda yukarı; boyunda kontrol noktalarındaki ipuçları arasında yumuşak geçiş.
local function dorsalAt(s)
	local hint = V(0, 1, 0)
	if s > S_RISE then
		local prevArc, prevHint = S_RISE, V(0, 1, 0)
		hint = NECK[#NECK][2]
		for i, n in NECK do
			local a = controlArc[SPIRAL_POINTS + i]
			if s <= a then
				hint = lerp(prevHint.Unit, n[2].Unit, (s - prevArc) / math.max(1e-6, a - prevArc))
				break
			end
			prevArc, prevHint = a, n[2]
		end
	end
	local d = dirAt(s)
	return (hint - d * hint:Dot(d)).Unit
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
-- Gövde kemikleri g1..gN kuyruktan başa doğru dizilir; kök sarmalın ortasındaki kemiktir.
local BONE_STEP = 4.5
local boneArcs = {}
do
	local s = BONE_STEP
	while s < TOTAL - 2 do
		table.insert(boneArcs, s)
		s += BONE_STEP
	end
end
local N = #boneArcs
local ROOT = 8
addBone("g" .. ROOT, nil, curveAt(boneArcs[ROOT]))
for k = ROOT + 1, N do
	addBone("g" .. k, "g" .. (k - 1), curveAt(boneArcs[k]))
end
local headPivot = curveAt(TOTAL)
addBone("head", "g" .. N, headPivot)
local headFrame = CFrame.new(headPivot) * CFrame.Angles(rad(-25), 0, 0)
local function H(x, y, z)
	return headFrame * V(x, y, z)
end
local function HD(x, y, z)
	return headFrame:VectorToWorldSpace(V(x, y, z))
end
local function HCF(x, y, z)
	return headFrame * CFrame.new(x, y, z)
end
addBone("jaw", "head", H(0, -0.3, 0.6))
addBone("tongue", "head", H(0, -0.55, -1.6))
for k = ROOT - 1, 1, -1 do
	addBone("g" .. k, "g" .. (k + 1), curveAt(boneArcs[k]))
end

--- Eğrinin `s` noktasını hangi kemik taşır: kökten başa doğru kemik kendi pivotundan sonrasını,
--- kökten kuyruğa doğru kemik kendi pivotundan öncesini döndürür.
local function boneAt(s: number): string
	if s >= TOTAL then
		return "head"
	end
	if s >= boneArcs[ROOT] then
		local k = ROOT
		while k < N and boneArcs[k + 1] <= s do
			k += 1
		end
		return "g" .. k
	end
	local k = ROOT
	while k > 1 and boneArcs[k - 1] > s do
		k -= 1
	end
	return "g" .. k
end

-- ═════════════════════════════ GÖVDE ═════════════════════════════
local bodyControls = {}
do
	local s = 0
	while s < TOTAL do
		local w = widthAt(s)
		table.insert(bodyControls, { pos = curveAt(s), w = w, h = w * 0.9, bone = boneAt(s) })
		s += 0.5
	end
	table.insert(bodyControls, { pos = headPivot, w = 3.0, h = 2.7, bone = boneAt(TOTAL - 0.01) })
	table.insert(bodyControls, { pos = H(0, 0.25, -1.0), w = 2.9, h = 2.5, bone = "head" })
end
local bodyParts = smoothTube("Govde", "Govde", bodyControls, 1.3, 5.0, C.scale, M.Slate)

--- Eğrinin `s` noktasından `ray` yönünde gövde yüzeyi.
local function surfacePoint(s, ray)
	local origin = curveAt(s)
	return origin + ray * surfaceDistance(bodyParts, origin, ray)
end

-- Beyaz ve koyu lekeler: yüzeye yatık yassı elipsler (görseldeki alacalı desen).
local s = 4
while s < TOTAL - 2 do
	local w = widthAt(s)
	for _ = 1, 2 do
		if rand() < 0.45 then
			local dir, dorsal = dirAt(s), dorsalAt(s)
			local lateral = dir:Cross(dorsal).Unit
			local a = jitter(rad(80))
			local ray = (dorsal * math.cos(a) + lateral * math.sin(a)).Unit
			local pos = surfacePoint(s, ray) - ray * 0.1
			local spin = rand() * math.pi
			local tangent = (dir * math.cos(spin) + ray:Cross(dir).Unit * math.sin(spin)).Unit
			local size = (0.6 + w * 0.22) * (0.8 + 0.5 * rand())
			local dark = rand() < 0.3
			-- her leke üst üste binen iki yassı elipsten: kenarları bulut gibi düzensiz olur
			for blob = 1, 2 do
				local shift = if blob == 1 then V(0, 0, 0) else (tangent * jitter(size * 0.45) + ray:Cross(tangent).Unit * jitter(size * 0.35))
				local k = if blob == 1 then 1 else 0.55 + 0.25 * rand()
				ellipsoid("Leke", "Govde", boneAt(s), lookFrame(pos + shift, tangent, ray), V(size * k * (0.7 + 0.4 * rand()), 0.34, size * k * (1.0 + 0.5 * rand())),
					if dark then C.scaleDark else C.patch, if dark then M.Slate else M.Snow, { shadow = false, query = false })
			end
		end
	end
	s += 2.0
end

-- Sırt boyunca iki sıra buz tüyü: kuyruğa doğru yatar, boyunda daha iridir.
s = 10
local row = 0
while s < TOTAL - 1.5 do
	local w = widthAt(s)
	local dir, dorsal = dirAt(s), dorsalAt(s)
	local lateral = dir:Cross(dorsal).Unit
	for _, side in { 1, -1 } do
		local a = side * rad(28 + jitter(8)) + (if row % 2 == 0 then rad(6) else -rad(6))
		local ray = (dorsal * math.cos(a) + lateral * math.sin(a)).Unit
		local base = surfacePoint(s, ray) - ray * 0.25
		local length = (1.2 + 0.5 * w) * (0.85 + 0.3 * rand()) * (if s > S_RISE then 1.2 else 1)
		feather("Govde", boneAt(s), base, ray * 0.45 - dir, ray, length, length * 0.5)
	end
	row += 1
	s += 1.55
end
-- Sarmalın dış kenarında seyrek tüy saçakları.
s = 12
while s < S_RISE - 2 do
	local p = curveAt(s)
	local dir = dirAt(s)
	local outward = V(p.X, 0, p.Z).Unit
	local ray = (outward + V(0, 0.35, 0)).Unit
	local base = surfacePoint(s, ray) - ray * 0.2
	local length = (1.0 + 0.4 * widthAt(s)) * (0.85 + 0.3 * rand())
	feather("Govde", boneAt(s), base, ray * 0.4 - dir, ray, length, length * 0.5)
	s += 3.0 + rand()
end

-- Boynun önünde açık renkli karın plakaları ve aralarındaki çizgiler.
do
	local strip = {}
	local nextSeam = S_RISE + 1.8
	local s2 = S_RISE + 1
	while s2 <= TOTAL - 1.2 do
		local dir, front = dirAt(s2), -dorsalAt(s2)
		local w = widthAt(s2)
		local center = surfacePoint(s2, front) - front * 0.9
		table.insert(strip, { pos = center, w = w * 0.6, h = 2.1, bone = boneAt(s2) })
		if s2 >= nextSeam then
			nextSeam += 1.5
			local right = dir:Cross(front).Unit
			ellipsoid("KarinCizgi", "Govde", boneAt(s2), CFrame.fromMatrix(center, right, dir, front), V(w * 0.62, 0.2, 2.25),
				C.seam, M.SmoothPlastic, { shadow = false, query = false })
		end
		s2 += 0.8
	end
	smoothTube("Karin", "Govde", strip, 1.1, 3.8, C.belly, M.Slate)
end

-- ═════════════════════════════ BAŞ ═════════════════════════════
local function hctl(x, y, z, w, h, bone)
	return { pos = H(x, y, z), w = w, h = h, bone = bone }
end
local skull = smoothTube("Kafa", "Kafa", {
	hctl(0, 0.3, 1.2, 3.0, 2.5, "head"),
	hctl(0, 0.45, -0.8, 3.5, 2.6, "head"),
	hctl(0, 0.35, -2.8, 3.1, 2.2, "head"),
	hctl(0, 0.2, -4.6, 2.4, 1.7, "head"),
	hctl(0, 0.1, -5.8, 1.7, 1.25, "head"),
	hctl(0, 0.05, -6.5, 1.1, 0.85, "head"),
}, 0.9, 3.2, C.scale, M.Slate)
local jaw = smoothTube("Cene", "Kafa", {
	hctl(0, -0.75, 0.6, 2.8, 1.2, "jaw"),
	hctl(0, -0.95, -1.6, 2.7, 1.1, "jaw"),
	hctl(0, -0.9, -3.8, 2.1, 0.9, "jaw"),
	hctl(0, -0.8, -5.3, 1.4, 0.7, "jaw"),
	hctl(0, -0.75, -6.0, 0.9, 0.5, "jaw"),
}, 0.9, 3.0, C.scale, M.Slate)
local mouth = ellipsoid("Agiz", "Kafa", "head", HCF(0, -0.55, -3.2), V(2.2, 0.6, 5.4), C.mouth, M.SmoothPlastic, { shadow = false })
ellipsoid("AgizAlt", "Kafa", "jaw", HCF(0, -0.72, -3.0), V(2.0, 0.4, 5.0), C.mouthLow, M.SmoothPlastic, { shadow = false })
-- çatal dil: ağzın içinde durur, dilin kemiği öne kayınca dışarı çıkar
ellipsoid("Dil", "Kafa", "tongue", HCF(0, -0.55, -3.6), V(0.24, 0.14, 4.2), C.tongue, M.SmoothPlastic, { shadow = false, query = false })
for _, sgn in { 1, -1 } do
	ellipsoid("Dil", "Kafa", "tongue", HCF(sgn * 0.14, -0.55, -5.9) * CFrame.Angles(0, sgn * rad(14), 0), V(0.14, 0.12, 1.0), C.tongue, M.SmoothPlastic,
		{ shadow = false, query = false })
end
local headParts = {}
for _, p in skull do
	table.insert(headParts, p)
end
for _, sgn in { 1, -1 } do
	-- mor göz ve dikey göz bebeği
	local origin = H(0, 0.5, -2.4)
	local eyeDir = HD(sgn, 0.55, 0).Unit
	local eyePos = origin + eyeDir * (surfaceDistance(skull, origin, eyeDir) - 0.1)
	local eyeRot = headFrame.Rotation * CFrame.Angles(0, sgn * rad(12), sgn * rad(-20))
	ellipsoid("Goz", "Kafa", "head", CFrame.new(eyePos) * eyeRot, V(0.34, 0.52, 0.95), C.eye, M.Neon, { shadow = false })
	ellipsoid("GozBebegi", "Kafa", "head", CFrame.new(eyePos + eyeDir * 0.14) * eyeRot, V(0.1, 0.44, 0.14), C.pupil, M.SmoothPlastic, { shadow = false })
	-- kaşın üstünde küçük tüy
	local browDir = HD(sgn * 0.6, 1, 0).Unit
	local browBase = origin + browDir * (surfaceDistance(skull, origin, browDir) - 0.15)
	feather("Kafa", "head", browBase, HD(sgn * 0.45, 0.5, 1), browDir, 1.8, 0.6)
	-- burun delikleri
	local noseOrigin = H(0, 0.1, -5.8)
	local noseDir = HD(sgn * 0.45, 1, -0.2).Unit
	ellipsoid("BurunDeligi", "Kafa", "head", CFrame.new(noseOrigin + noseDir * (surfaceDistance(skull, noseOrigin, noseDir) - 0.04)) * headFrame.Rotation,
		V(0.26, 0.18, 0.36), C.nostril, M.SmoothPlastic, { shadow = false })
	-- iki uzun zehir dişi ve küçük dişler
	local fangOrigin = H(0, 0.1, -5.0)
	local fangDir = HD(sgn * 0.5, -1, 0).Unit
	spike("ZehirDisi", "Kafa", "head", fangOrigin + fangDir * surfaceDistance(skull, fangOrigin, fangDir) + HD(0, 0.15, 0), HD(0, -1, -0.15), HD(0, 0, -1),
		1.1, 0.35, 0.22, C.fang, M.SmoothPlastic, { shadow = false })
	for _, z in { -2.4, -3.3, -4.2 } do
		local o = H(0, 0.1, z)
		local d = HD(sgn * 0.55, -1, 0).Unit
		spike("Dis", "Kafa", "head", o + d * surfaceDistance(skull, o, d) + HD(0, 0.1, 0), HD(0, -1, 0), HD(0, 0, -1), 0.4, 0.25, 0.16, C.fang, M.SmoothPlastic, { shadow = false })
	end
end
-- başın üstünde tepe tüyleri ve başı çevreleyen iki sıra tüy yakalık
for i, z in { -2.6, -1.5, -0.3, 0.9 } do
	local origin = H(0, 0.3, z)
	local up = HD(0, 1, 0)
	feather("Kafa", "head", origin + up * (surfaceDistance(skull, origin, up) - 0.2), HD(0, 0.35, 1), up, 1.8 + i * 0.6, 0.9 + i * 0.12)
end
for ring = 1, 2 do
	local z = if ring == 1 then 0.6 else 1.6
	local count = if ring == 1 then 12 else 14
	for k = 0, count - 1 do
		local a = rad(100) + (k + (if ring == 2 then 0.5 else 0)) * (rad(340) / count)
		local out = HD(math.cos(a), math.sin(a), 0)
		local origin = H(0, 0.1, z)
		local below = math.sin(a) < -0.3
		local surfaceParts = if below then jaw else skull
		local base = origin + out * math.max(1.0, surfaceDistance(surfaceParts, origin, out) - 0.3)
		local length = (if ring == 1 then 3.4 else 5.2) * (0.9 + 0.25 * rand())
		feather("Kafa", if below then "jaw" else "head", base, out * 0.9 + HD(0, 0, 1), out, length, length * 0.42)
	end
end

-- ═════════════════════════════ BUZ KRİSTALLERİ ═════════════════════════════
-- Yılanın çevresinde karla kaplı zemin üstünde buz kristali kümeleri (kemiğe bağlı değildir).
for _, spot in { V(17, 0, -6), V(-16.5, 0, 7), V(8, 0, 17.5), V(-8.5, 0, -17), V(15.5, 0, 11) } do
	ellipsoid("KarYigini", "BuzKristalleri", nil, CFrame.new(spot + V(0, 0.1, 0)) * CFrame.Angles(0, rand() * math.pi, 0),
		V(4.6 + rand() * 1.4, 0.9, 3.6 + rand()), C.snow, M.Snow, { query = false })
	for i = 1, 3 do
		local h = 2.4 + rand() * 3.6 * (if i == 1 then 1 else 0.7)
		local w = 0.8 + rand() * 0.6
		local cf = CFrame.new(spot + V(jitter(1.3), 0, jitter(1.1))) * CFrame.Angles(jitter(0.4), rand() * math.pi, jitter(0.4)) * CFrame.new(0, h * 0.42, 0)
		local crystal = basePart("Part", "Kristal", "BuzKristalleri", nil, cf, V(w, h, w), C.crystal, M.Glass, { query = false, transparency = 0.25 })
		crystal.Reflectance = 0.15
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
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Kükreme: ağızdan buz nefesi (soğuk sis bulutu ve parıldayan buz kristalleri).
local breathOut = attachment(mouth, "AyazCikisi", CFrame.new(0, 0, -2.9))
emitter(breathOut, "Ayaz", {
	Texture = SMOKE, Color = seq({ { 0, RGB(255, 255, 255) }, { 0.5, RGB(214, 234, 255) }, { 1, RGB(170, 200, 250) } }),
	LightEmission = 0.35, LightInfluence = 0.3, Size = nums({ { 0, 1.4 }, { 0.5, 5 }, { 1, 9 } }),
	Transparency = nums({ { 0, 0.2 }, { 0.7, 0.5 }, { 1, 1 } }), Lifetime = NumberRange.new(0.9, 1.3), Rate = 110,
	Speed = NumberRange.new(30, 42), SpreadAngle = Vector2.new(12, 12), Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-60, 60), Drag = 1.5, Acceleration = V(0, -2, 0), EmissionDirection = Enum.NormalId.Front,
	Enabled = false, attributes = { AyazNefesi = true },
})
emitter(breathOut, "AyazKristali", {
	Texture = SPARKLE, Color = seq({ { 0, RGB(255, 255, 255) }, { 1, RGB(170, 215, 255) } }), LightEmission = 1, LightInfluence = 0,
	Size = nums({ { 0, 0.7 }, { 1, 0.15 } }), Lifetime = NumberRange.new(0.6, 0.9), Rate = 80, Speed = NumberRange.new(34, 50),
	SpreadAngle = Vector2.new(9, 9), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
	EmissionDirection = Enum.NormalId.Front, Enabled = false, attributes = { AyazNefesi = true },
})
local mouthLight = Instance.new("PointLight")
mouthLight.Name = "AgizIsigi"
mouthLight.Color = RGB(170, 210, 255)
mouthLight.Range = 22
mouthLight.Brightness = 0
mouthLight.Shadows = false
mouthLight.Parent = mouth
-- Gözlerin çevresinde hafif soğuk ışık
local headLight = Instance.new("PointLight")
headLight.Name = "SogukIsik"
headLight.Color = RGB(190, 200, 255)
headLight.Range = 12
headLight.Brightness = 0.6
headLight.Shadows = false
headLight.Parent = skull[2]

-- Burun deliklerinden nefesle birlikte çıkan buhar (hızını animasyon script'i nefese göre ayarlar).
local noseOut = attachment(skull[#skull], "BurunBuhari", CFrame.new(0, 0.2, -0.4) * CFrame.Angles(rad(-20), 0, 0))
emitter(noseOut, "Buhar", {
	Texture = SMOKE, Color = seq({ { 0, RGB(250, 252, 255) }, { 1, RGB(210, 225, 250) } }), LightInfluence = 0.6,
	Size = nums({ { 0, 0.4 }, { 1, 2.2 } }), Transparency = nums({ { 0, 0.45 }, { 1, 1 } }), Lifetime = NumberRange.new(1.0, 1.6),
	Rate = 0, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(12, 12), Drag = 1, Acceleration = V(0, -0.5, 0),
	EmissionDirection = Enum.NormalId.Front, attributes = { BurunBuhari = true, TemelHiz = 12 },
})

-- Yılanın çevresinde süzülen kar taneleri ve yerde sürünen soğuk sis.
for i, k in { 6, 18, 30 } do
	local part = bodyParts[math.min(#bodyParts, k)]
	local a = attachment(part, "KarNoktasi", CFrame.new(0, 3, 0))
	emitter(a, "KarTanesi", {
		Texture = SPARKLE, Color = seq({ { 0, RGB(255, 255, 255) }, { 1, RGB(200, 225, 255) } }), LightEmission = 0.6,
		Size = nums({ { 0, 0.3 }, { 1, 0.15 } }), Lifetime = NumberRange.new(3, 5), Rate = 6, Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		Acceleration = V(0, -1.2, 0),
	})
	if i ~= 2 then
		emitter(part, "Sis", {
			Texture = SMOKE, Color = seq({ { 0, RGB(245, 250, 255) }, { 1, RGB(220, 232, 250) } }), LightInfluence = 0.8,
			Size = nums({ { 0, 3 }, { 1, 9 } }), Transparency = nums({ { 0, 0.72 }, { 1, 1 } }), Lifetime = NumberRange.new(4, 6),
			Rate = 2, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(60, 60), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-10, 10), Acceleration = V(0, 0.3, 0),
		})
	end
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

local function collider(name, cf, size, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = folder("Carpisma")
end
collider("HalkaCarpisma", CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, rad(90)), V(5.2, 30, 30), Enum.PartType.Cylinder)
collider("BoyunCarpisma", CFrame.new(-1.6, 13.5, 4.2) * CFrame.Angles(rad(-8), 0, 0), V(5.4, 19, 5.4))

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
table.insert(lines, "")
-- Gövde kemiklerinin türü: kuyruk ucu, yerdeki halka ya da yükselen boyun; `order` kökten dışa doğru sıra.
local TAIL_END = 3
local firstNeck = N + 1
for k = 1, N do
	if boneArcs[k] > S_RISE then
		firstNeck = k
		break
	end
end
table.insert(lines, "Rig.body = {")
for k = 1, N do
	local kind, order, count
	if k <= TAIL_END then
		kind, order, count = "tail", TAIL_END - k + 1, TAIL_END
	elseif k < firstNeck then
		kind, order, count = "coil", k, firstNeck - 1
	else
		kind, order, count = "neck", k - firstNeck + 1, N - firstNeck + 1
	end
	table.insert(lines, string.format("\t{ bone = %d, kind = %q, order = %d, count = %d },", boneIndex["g" .. k], kind, order, count))
end
table.insert(lines, "}")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "YilanRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. fs.readFile("src/rig.luau")
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("BuzYilani.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("BuzYilani.rbxmx yazıldı: %d parça, %d kemik (%d boyun), gövde uzunluğu %.1f stud", count, #bones, N - firstNeck + 1, TOTAL))
for name, f in folders do
	print(string.format("  %-15s %d", name, #f:GetChildren()))
end
