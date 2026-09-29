--[[
	Üç Başlı Ejderha modelini üretir: lune run src/build.luau   (ucbasli/ klasöründen)
	Çıktı: UcBasliEjderha.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Her parça bir kemiğe bağlanır; parçaların kemiğe göre konumları, kanat zarı üçgenleri ve
	ağızlardan çıkan altın şimşeklerin verisi "UcBasliRig" ModuleScript'ine veri olarak yazılır.
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
local seed = 3030303
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (görseldeki altın pullar, kahverengi yeleler, kırmızı gözler ve çizgiler) ───
local RGB = Color3.fromRGB
local C = {
	scale = RGB(218, 158, 42),
	scaleDark = RGB(172, 112, 28),
	belly = RGB(240, 200, 108),
	seam = RGB(160, 100, 26),
	horn = RGB(246, 214, 130),
	hornTip = RGB(252, 236, 186),
	mane = RGB(112, 64, 34),
	membrane = RGB(214, 150, 44),
	wingBone = RGB(190, 128, 30),
	claw = RGB(62, 44, 30),
	tooth = RGB(244, 232, 204),
	eye = RGB(235, 32, 22),
	mouth = RGB(122, 34, 26),
	tongue = RGB(160, 54, 44),
	stripe = RGB(196, 36, 28),
	nostril = RGB(60, 36, 20),
	bolt = RGB(255, 226, 110),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "UcBasliEjderha"
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
		up = V(0, 0, 1)
	end
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- a'dan b'ye uzanan çerçeve: -Z (LookVector) b'ye bakar.
local function along(a, b, upHint)
	return lookFrame((a + b) / 2, b - a, upHint)
end

--- a ile b arasına gerilmiş elips (uzuvlar, parmaklar).
local function segment(prefix, group, bone, a, b, w, h, color, material, opts)
	opts = opts or {}
	local len = (b - a).Magnitude * (opts.extend or 1.25)
	return ellipsoid(prefix, group, bone, along(a, b, opts.up), V(w, h, len), color, material, opts)
end

--- Diken/pençe/diş/boynuz ucu: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
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
	local function dir(s)
		return (at(s + 0.4).pos - at(s - 0.4).pos).Unit
	end
	return { at = at, dir = dir, total = total }
end

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir boru. `spacing` elips
--- merkezleri arası, `length` her elipsin boyu; length/spacing ≥ 3 iken halka izi kalmaz.
--- Uçtaki elipsler zincirin dışına taşmaz, uçlar doğal biçimde incelir.
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

--- Catmull-Rom ile yumuşatılmış eğri noktaları (kıvrık boynuzlar için).
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

--- Zincirin bir tarafı boyunca sıra sıra diken (sırt dikenleri, yeleler). `sideOf(dir)` dikenin
--- çıktığı yüzey yönünü, `leanOf(dir)` ucunun yattığı yönü verir.
local function spikeRow(prefix, group, surfaceParts, controls, opts)
	local sampler = chainSampler(controls)
	local s, k = opts.from, 0
	while s <= opts.to do
		local c = sampler.at(s)
		local dir = sampler.dir(s)
		local outward = opts.sideOf(dir)
		local lateral = dir:Cross(outward).Unit
		local base = c.pos + outward * (surfaceDistance(surfaceParts, c.pos, outward) - 0.35)
		if opts.stagger then
			base += lateral * (if k % 2 == 0 then opts.stagger else -opts.stagger)
		end
		local out = (outward + lateral * jitter(opts.wobble or 0.12)).Unit
		local h = opts.heightAt(s) * (0.8 + 0.4 * rand())
		spike(prefix, group, c.bone, base, out, opts.leanOf(dir), h, h * (opts.lengthRatio or 0.7), opts.thickness or 0.45, opts.color, opts.material)
		s += opts.spacing * (0.85 + 0.3 * rand())
		k += 1
	end
end

--- Karın/boyun önündeki açık renkli plaka şeridi ve plakaları ayıran ince koyu çizgiler.
local function plateStrip(prefix, group, surfaceParts, controls, opts)
	local sampler = chainSampler(controls)
	local strip = {}
	local nextSeam = opts.from + opts.seamSpacing * 0.5
	local s = opts.from
	while s <= opts.to do
		local c = sampler.at(s)
		local dir = sampler.dir(s)
		local front = opts.frontOf(dir)
		local center = c.pos + front * (surfaceDistance(surfaceParts, c.pos, front) - opts.depth * 0.43)
		table.insert(strip, { pos = center, w = c.w * opts.widthRatio, h = opts.depth, bone = c.bone })
		if s >= nextSeam then
			nextSeam += opts.seamSpacing
			local right = dir:Cross(front).Unit
			ellipsoid(prefix .. "Cizgi", group, c.bone, CFrame.fromMatrix(center, right, dir, front),
				V(c.w * opts.widthRatio * 1.02, 0.2, opts.depth * 1.08), C.seam, M.SmoothPlastic, { shadow = false, query = false })
		end
		s += 0.8
	end
	smoothTube(prefix, group, strip, 1.2, 4.2, C.belly, M.Slate)
end

local function ctl(pos, w, h, bone)
	return { pos = pos, w = w, h = h, bone = bone }
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("pelvis", nil, V(0, 11.5, 4.2))
addBone("spine1", "pelvis", V(0, 14.6, 2.6))
addBone("chest", "spine1", V(0, 17.8, 0.8))

-- Üç boyun: ortadaki en uzun ve dik; yandakiler dışa ve öne kıvrılır.
local NECK_ORDER = { "M", "L", "R" }
local NECKS = {
	M = {
		base = V(0, 19.6, 0.4), yaw = 0, scale = 1.15, thick = 1.08, style = "hilal",
		pivots = { V(0, 21.6, -0.4), V(0, 25.2, -1.0), V(0, 28.8, -0.8), V(0, 32.0, -1.4) }, head = V(0, 34.4, -2.8),
	},
	L = {
		base = V(2.6, 19.2, 0.6), yaw = rad(-24), scale = 1.0, thick = 1.0, style = "tac",
		pivots = { V(2.9, 21.2, -0.4), V(5.4, 23.9, -1.2), V(7.8, 26.5, -1.4), V(9.8, 28.7, -2.2) }, head = V(11.0, 30.5, -3.6),
	},
	R = {
		base = V(-2.6, 19.2, 0.6), yaw = rad(24), scale = 1.0, thick = 1.0, style = "hilal",
		pivots = { V(-2.9, 21.2, -0.4), V(-5.6, 24.2, -1.0), V(-8.0, 27.2, -1.0), V(-9.8, 29.8, -1.8) }, head = V(-10.8, 31.8, -3.2),
	},
}
for _, key in NECK_ORDER do
	local n = NECKS[key]
	for i, p in n.pivots do
		addBone("neck" .. key .. i, if i == 1 then "chest" else "neck" .. key .. (i - 1), p)
	end
	addBone("head" .. key, "neck" .. key .. "4", n.head)
	n.frame = CFrame.new(n.head) * CFrame.Angles(0, n.yaw, 0) * CFrame.Angles(rad(-6), 0, 0)
	addBone("jaw" .. key, "head" .. key, n.frame * (V(0, -0.4, -0.8) * n.scale))
end

local TAILS = {
	L = { pivots = { V(0.9, 10.4, 7.8), V(1.9, 8.8, 11.8), V(3.1, 7.0, 15.8), V(4.2, 5.3, 19.8), V(5.2, 3.8, 23.8), V(6.0, 2.6, 27.8) }, tip = V(6.6, 1.8, 31.6), sgn = 1 },
	R = { pivots = { V(-0.9, 10.6, 7.6), V(-2.1, 9.2, 11.4), V(-3.5, 7.6, 15.2), V(-4.9, 6.0, 19.0), V(-6.1, 4.6, 22.8), V(-7.1, 3.4, 26.6) }, tip = V(-7.9, 2.6, 30.4), sgn = -1 },
}
for _, side in { "L", "R" } do
	for i, p in TAILS[side].pivots do
		addBone("tail" .. side .. i, if i == 1 then "pelvis" else "tail" .. side .. (i - 1), p)
	end
end

for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	addBone("thigh" .. side, "pelvis", V(s * 3.8, 10.6, 4.4))
	addBone("shin" .. side, "thigh" .. side, V(s * 5.0, 6.6, 0.8))
	addBone("foot" .. side, "shin" .. side, V(s * 4.8, 2.5, 3.8))
	addBone("wingRoot" .. side, "chest", V(s * 3.8, 19.2, 3.2))
	addBone("wingElbow" .. side, "wingRoot" .. side, V(s * 13.0, 27.5, 7.5))
	addBone("wingWrist" .. side, "wingElbow" .. side, V(s * 23.0, 33.5, 5.0))
	for f = 1, 4 do
		addBone("finger" .. side .. f, "wingWrist" .. side, V(s * 23.0, 33.5, 5.0))
	end
end

-- ═════════════════════════════ GÖVDE ═════════════════════════════
local bodyChain = {
	ctl(V(0, 7.2, 6.4), 6.8, 6.0, "pelvis"),
	ctl(V(0, 8.8, 5.8), 7.8, 7.2, "pelvis"),
	ctl(V(0, 11.5, 4.6), 9.2, 8.2, "pelvis"),
	ctl(V(0, 14.5, 3.0), 10.0, 8.8, "spine1"),
	ctl(V(0, 17.4, 1.2), 10.4, 9.0, "chest"),
	ctl(V(0, 19.6, 0.2), 9.6, 7.4, "chest"),
	ctl(V(0, 20.8, -0.2), 7.2, 5.4, "chest"),
}
local bodyParts = smoothTube("Govde", "Govde", bodyChain, 1.3, 6.0, C.scale, M.Slate)
local bodySampler = chainSampler(bodyChain)
local function frontOfBody(dir)
	return dir:Cross(V(1, 0, 0)).Unit -- zincir yukarı ve öne gider; bu vektör karına bakar
end
plateStrip("Karin", "Govde", bodyParts, bodyChain, {
	from = 1.8, to = bodySampler.total - 1.6, seamSpacing = 1.6, widthRatio = 0.6, depth = 2.4, frontOf = frontOfBody,
})
-- sırtta kısa dikenler
spikeRow("SirtDikeni", "Govde", bodyParts, bodyChain, {
	from = 2.5, to = bodySampler.total - 3.2, spacing = 1.9, color = C.horn, thickness = 0.5,
	sideOf = function(dir)
		return -frontOfBody(dir)
	end,
	leanOf = function(dir)
		return -dir
	end,
	heightAt = function()
		return 1.6
	end,
})
-- göğsün iki yanındaki üç kırmızı çizgi (görseldeki işaret)
for _, s in { 1, -1 } do
	local arc = bodySampler.total * 0.55
	local c = bodySampler.at(arc)
	local dir = bodySampler.dir(arc)
	local side = V(s, 0, 0)
	local front = frontOfBody(dir)
	for k = 0, 2 do
		local ray = (side * math.cos(rad(22 + k * 9)) + front * math.sin(rad(22 + k * 9))).Unit
		local pos = c.pos + ray * (surfaceDistance(bodyParts, c.pos, ray) - 0.08)
		ellipsoid("KirmiziCizgi", "Govde", c.bone, lookFrame(pos, dir, ray), V(0.42, 0.3, 2.6 - k * 0.2), C.stripe, M.SmoothPlastic, { shadow = false })
	end
end

-- ═════════════════════════════ BOYUNLAR VE BAŞLAR ═════════════════════════════
local bolts = {}
local function makeHead(key: string, n)
	local k, frame = n.scale, n.frame
	local headBone, jawBone = "head" .. key, "jaw" .. key
	local group = "Bas" .. key
	local function P(x, y, z)
		return frame * (V(x, y, z) * k)
	end
	local function D(x, y, z)
		return frame:VectorToWorldSpace(V(x, y, z))
	end
	local function CF(x, y, z)
		return frame * CFrame.new(V(x, y, z) * k)
	end
	local function hc(x, y, z, w, h, bone)
		return ctl(P(x, y, z), w * k, h * k, bone)
	end

	local skull = smoothTube("Kafa", group, {
		hc(0, 0.5, 1.0, 2.6, 2.8, headBone),
		hc(0, 0.7, -0.8, 3.0, 3.1, headBone),
		hc(0, 0.45, -2.8, 2.4, 2.1, headBone),
		hc(0, 0.3, -4.8, 1.9, 1.6, headBone),
		hc(0, 0.22, -6.3, 1.5, 1.25, headBone),
		hc(0, 0.18, -7.3, 1.0, 0.85, headBone),
	}, 0.9 * k, 3.0 * k, C.scale, M.Slate)
	local jaw = smoothTube("Cene", group, {
		hc(0, -0.75, -0.2, 2.4, 1.5, jawBone),
		hc(0, -1.1, -2.3, 2.1, 1.3, jawBone),
		hc(0, -1.0, -4.4, 1.6, 1.0, jawBone),
		hc(0, -0.85, -6.2, 1.1, 0.8, jawBone),
		hc(0, -0.8, -6.8, 0.8, 0.55, jawBone),
	}, 0.9 * k, 2.8 * k, C.scale, M.Slate)
	local mouth = ellipsoid("Agiz", group, headBone, CF(0, -0.55, -3.8), V(1.8, 0.7, 6.0) * k, C.mouth, M.SmoothPlastic, { shadow = false })
	ellipsoid("Dil", group, jawBone, CF(0, -0.75, -3.4), V(1.2, 0.4, 4.0) * k, C.tongue, M.SmoothPlastic, { shadow = false })

	for _, s in { 1, -1 } do
		-- kırmızı göz ve kaş çıkıntısı
		local origin = P(0, 0.9, -2.6)
		local eyeDir = D(s, 0.4, 0).Unit
		local eyePos = origin + eyeDir * (surfaceDistance(skull, origin, eyeDir) - 0.1)
		ellipsoid("Goz", group, headBone, CFrame.new(eyePos) * frame.Rotation * CFrame.Angles(0, s * rad(15), 0), V(0.35, 0.45, 0.8) * k, C.eye, M.Neon, { shadow = false })
		local browDir = D(s * 0.7, 1, 0.1).Unit
		local browPos = origin + browDir * (surfaceDistance(skull, origin, browDir) - 0.18)
		ellipsoid("Kas", group, headBone, CFrame.new(browPos) * frame.Rotation * CFrame.Angles(0, 0, -s * rad(30)), V(0.9, 0.5, 1.8) * k, C.scaleDark, M.Slate)
		-- burun delikleri
		local noseOrigin = P(0, 0.2, -6.4)
		local noseDir = D(s * 0.5, 1, 0).Unit
		ellipsoid("BurunDeligi", group, headBone, CFrame.new(noseOrigin + noseDir * (surfaceDistance(skull, noseOrigin, noseDir) - 0.04)) * frame.Rotation,
			V(0.3, 0.22, 0.45) * k, C.nostril, M.SmoothPlastic, { shadow = false })
		-- dişler
		for i, z in { -2.4, -3.6, -4.8, -6.0 } do
			local o = P(0, 0.2, z)
			local d = D(s * 0.6, -1, 0).Unit
			spike("Dis", group, headBone, o + d * surfaceDistance(skull, o, d) + D(0, 0.12, 0), D(0, -1, 0), D(0, 0, -1),
				(if i == 4 then 0.8 else 0.55) * k, 0.3 * k, 0.2 * k, C.tooth, M.SmoothPlastic, { shadow = false })
		end
		for _, z in { -3.0, -4.3, -5.6 } do
			local o = P(0, -1.0, z)
			local d = D(s * 0.6, 1, 0).Unit
			spike("AltDis", group, jawBone, o + d * surfaceDistance(jaw, o, d) - D(0, 0.12, 0), D(0, 1, 0), D(0, 0, -1),
				0.5 * k, 0.28 * k, 0.2 * k, C.tooth, M.SmoothPlastic, { shadow = false })
		end
		-- ana boynuzlar: hilal (yukarı kalkıp geriye kıvrılır) ya da taç (dışa ve geriye açılır)
		local hornPts = if n.style == "hilal"
			then { P(s * 0.8, 1.3, 0.4), P(s * 1.3, 2.8, 0.8), P(s * 1.6, 4.1, 2.0), P(s * 1.5, 4.8, 3.6), P(s * 1.1, 4.8, 4.9) }
			else { P(s * 0.8, 1.3, 0.4), P(s * 1.6, 2.4, 1.4), P(s * 2.3, 3.0, 2.9), P(s * 2.7, 3.2, 4.4) }
		local curve = smoothCurve(hornPts, 3)
		local controls = {}
		for i, pt in curve do
			local w = lerp(0.85, 0.2, (i - 1) / (#curve - 1)) * k
			table.insert(controls, ctl(pt, w, w, headBone))
		end
		smoothTube("Boynuz", group, controls, 0.55 * k, 1.7 * k, C.horn, M.SmoothPlastic)
		spike("BoynuzUcu", group, headBone, curve[#curve], curve[#curve] - curve[#curve - 1], D(0, 1, 0), 0.7 * k, 0.3 * k, 0.22 * k, C.hornTip, M.SmoothPlastic)
		-- yanak dikenleri
		spike("Yanak", group, headBone, P(s * 1.1, -0.3, -0.6), D(s, -0.2, 0.6), D(0, 0, 1), 1.0 * k, 0.6 * k, 0.3 * k, C.horn)
	end
	-- kafatasının arkasındaki taç dikenleri
	local crown = if n.style == "tac" then { -1.0, -0.5, 0, 0.5, 1.0 } else { -0.8, -0.27, 0.27, 0.8 }
	for _, x in crown do
		spike("Tac", group, headBone, P(x, 1.25, 0.9), D(x * 0.6, 0.55, 1), D(0, 1, 0), (1.5 + 0.6 * rand() + (if n.style == "tac" then 0.5 else 0)) * k, 0.7 * k, 0.3 * k, C.horn)
	end
	spike("BurunBoynuzu", group, headBone, P(0, 0.85, -5.6), D(0, 1, 0.3), D(0, 0, 1), 0.7 * k, 0.6 * k, 0.28 * k, C.horn)
	-- başın arkasındaki kahverengi yele perçemi
	for _, x in { -0.45, 0, 0.45 } do
		spike("Yele", group, headBone, P(x, 1.0, 1.3), D(x * 0.8, 0.25, 1), D(0, -1, 0), (1.8 + 0.6 * rand()) * k, 1.0 * k, 0.3 * k, C.mane, M.Slate)
	end

	-- Kükremede ağızdan çıkan altın şimşek: ağız ucundaki nokta ve başın ileri yönü.
	local boltParts = {}
	for _ = 1, 8 do
		local p = basePart("Part", "Simsek" .. key, "Simsekler", nil, CFrame.new(P(0, -0.55, -7.2)), V(0.4, 0.4, 1), C.bolt, M.Neon,
			{ shadow = false, query = false, transparency = 1 })
		table.insert(boltParts, p.Name)
	end
	table.insert(bolts, { bone = headBone, origin = P(0, -0.55, -6.9), forward = D(0, -0.06, -1).Unit, parts = boltParts, mouth = mouth })
	return mouth
end

local mouths = {}
for _, key in NECK_ORDER do
	local n = NECKS[key]
	local chain = { ctl(n.base, 4.6 * n.thick, 4.4 * n.thick, "chest") }
	local widths = { 4.2, 3.8, 3.5, 3.2 }
	for i, p in n.pivots do
		table.insert(chain, ctl(p, widths[i] * n.thick, widths[i] * n.thick * 0.95, "neck" .. key .. i))
	end
	table.insert(chain, ctl(n.head, 3.0 * n.thick, 2.9 * n.thick, "neck" .. key .. "4"))
	table.insert(chain, ctl(n.frame * (V(0, 0.5, -0.8) * n.scale), 2.6 * n.scale, 2.8 * n.scale, "head" .. key))
	local group = "Boyun" .. key
	local neckParts = smoothTube("Boyun", group, chain, 1.1, 5.0, C.scale, M.Slate)
	local sampler = chainSampler(chain)
	local function backOf(dir)
		local b = V(0, 0.2, 1)
		return (b - dir * b:Dot(dir)).Unit
	end
	-- boynun arkasında kahverengi yele: kılları aşağı doğru yatar
	spikeRow("Yele", group, neckParts, chain, {
		from = 1.4, to = sampler.total - 1.2, spacing = 1.05, stagger = 0.35, wobble = 0.3, color = C.mane, material = M.Slate,
		thickness = 0.32, lengthRatio = 0.75,
		sideOf = backOf,
		leanOf = function(dir)
			return -dir
		end,
		heightAt = function(s)
			return 1.5 + 0.9 * math.sin(math.clamp(s / sampler.total, 0, 1) * math.pi)
		end,
	})
	-- boynun önünde açık renkli plakalar
	plateStrip("BoyunPlaka", group, neckParts, chain, {
		from = 1.6, to = sampler.total - 1.6, seamSpacing = 1.7, widthRatio = 0.55, depth = 1.6,
		frontOf = function(dir)
			return -backOf(dir)
		end,
	})
	mouths[key] = makeHead(key, n)
end

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local hip, knee, ankle = pivotOf("thigh" .. side), pivotOf("shin" .. side), pivotOf("foot" .. side)
	local ball = V(s * 4.8, 0.9, 1.0)
	smoothTube("Uyluk", "Bacaklar", { ctl(hip + V(0, 0.8, 0.4), 4.4, 4.8, "thigh" .. side), ctl(knee, 3.2, 3.4, "thigh" .. side) }, 1.4, 4.6, C.scale, M.Slate)
	segment("UylukKasi", "Bacaklar", "thigh" .. side, hip + V(s * 0.5, 0.6, 1.0), knee + V(s * 0.2, 0.8, 1.2), 4.6, 5.4, C.scale, M.Slate, { extend = 1.1 })
	smoothTube("Incik", "Bacaklar", { ctl(knee, 3.2, 3.4, "shin" .. side), ctl(ankle, 2.3, 2.4, "shin" .. side) }, 1.3, 4.0, C.scale, M.Slate)
	spike("DizDikeni", "Bacaklar", "shin" .. side, knee + V(0, 0.2, -1.2), V(0, 0.3, -1), V(0, 1, 0), 1.3, 0.8, 0.4, C.horn)
	smoothTube("Ayak", "Bacaklar", { ctl(ankle, 2.2, 2.3, "foot" .. side), ctl(ball, 1.9, 1.6, "foot" .. side) }, 1.0, 3.0, C.scale, M.Slate)
	ellipsoid("Taban", "Bacaklar", "foot" .. side, CFrame.new(ball + V(0, -0.15, -0.4)), V(3.4, 1.4, 3.0), C.scaleDark, M.Slate)
	for _, dx in { -1.0, 0, 1.0 } do
		local base = ball + V(s * dx * 0.9, -0.2, -0.6)
		local tip = V(ball.X + s * dx * 1.5, 0.5, ball.Z - 3.0 + math.abs(dx) * 0.5)
		segment("Parmak", "Bacaklar", "foot" .. side, base, tip, 1.15, 1.0, C.scale, M.Slate)
		spike("Pence", "Bacaklar", "foot" .. side, tip + V(0, 0.05, -0.25), V(0, -0.25, -1), V(0, 1, 0), 1.4, 0.65, 0.45, C.claw)
	end
	spike("Pence", "Bacaklar", "foot" .. side, ball + V(-s * 0.9, 0.2, 1.0), V(-s * 0.3, -0.5, 1), V(0, 1, 0), 0.8, 0.45, 0.35, C.claw)
end

-- ═════════════════════════════ İKİ KUYRUK ═════════════════════════════
for _, side in { "L", "R" } do
	local tail = TAILS[side]
	local chain = { ctl(V(tail.sgn * 0.4, 11.4, 4.8), 5.0, 4.8, "pelvis") }
	local widths = { 4.2, 3.6, 3.0, 2.4, 1.9, 1.4 }
	for i, p in tail.pivots do
		table.insert(chain, ctl(p, widths[i], widths[i] * 0.95, "tail" .. side .. i))
	end
	table.insert(chain, ctl(tail.tip, 0.8, 0.8, "tail" .. side .. "6"))
	local tailParts = smoothTube("Kuyruk", "Kuyruk" .. side, chain, 1.6, 6.0, C.scale, M.Slate)
	local sampler = chainSampler(chain)
	spikeRow("KuyrukDikeni", "Kuyruk" .. side, tailParts, chain, {
		from = 4.0, to = sampler.total - 1.5, spacing = 1.9, color = C.horn, thickness = 0.4,
		sideOf = function(dir)
			local up = V(0, 1, 0)
			return (up - dir * up:Dot(dir)).Unit
		end,
		leanOf = function(dir)
			return dir
		end,
		heightAt = function(s)
			return lerp(2.2, 0.9, s / sampler.total)
		end,
	})
	-- kuyruk ucundaki diken demeti
	local tipDir = sampler.dir(sampler.total - 0.2)
	local bone = "tail" .. side .. "6"
	for _, d in { V(0, 1, 0), V(1, 0.3, 0), V(-1, 0.3, 0), V(0, -0.6, 0) } do
		local out = (tipDir * 0.8 + d).Unit
		spike("KuyrukUcu", "Kuyruk" .. side, bone, tail.tip - tipDir * 0.6, out, tipDir, 1.6, 0.8, 0.4, C.horn)
	end
end

-- ═════════════════════════════ KANATLAR ═════════════════════════════
local membranes = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local R, E, W = pivotOf("wingRoot" .. side), pivotOf("wingElbow" .. side), pivotOf("wingWrist" .. side)
	local F = { V(s * 37, 41, 9.0), V(s * 42, 30, 13.0), V(s * 37, 18.5, 14.5), V(s * 27, 10, 12.0) }
	local B = V(s * 3.6, 11.2, 5.8)
	local group = "Kanat" .. side

	ellipsoid("KanatOmuz", group, "wingRoot" .. side, CFrame.new(R), V(3.0, 3.0, 3.0), C.scale, M.Slate)
	smoothTube("KanatKemik", group, { ctl(R, 2.4, 2.4, "wingRoot" .. side), ctl(E, 1.8, 1.8, "wingRoot" .. side) }, 2.2, 6.5, C.wingBone, M.Slate)
	ellipsoid("KanatDirsek", group, "wingElbow" .. side, CFrame.new(E), V(2.1, 2.1, 2.1), C.wingBone, M.Slate)
	smoothTube("KanatKemik", group, { ctl(E, 1.8, 1.8, "wingElbow" .. side), ctl(W, 1.4, 1.4, "wingElbow" .. side) }, 2.2, 5.5, C.wingBone, M.Slate)
	ellipsoid("KanatBilek", group, "wingWrist" .. side, CFrame.new(W), V(1.7, 1.7, 1.7), C.wingBone, M.Slate)
	spike("KanatPencesi", group, "wingWrist" .. side, W + V(0, 0.5, -0.3), V(0, 0.5, -1), V(s, 0.5, 0), 1.8, 0.8, 0.45, C.claw)
	for i = 1, 3 do
		local p = lerp(R, E, i / 4)
		spike("KanatDikeni", group, "wingRoot" .. side, p + V(0, 0.8, 0), V(0, 1, -0.2), (E - R).Unit, 1.2, 0.7, 0.35, C.horn)
	end
	for f = 1, 4 do
		local bone = "finger" .. side .. f
		smoothTube("KanatParmak", group, { ctl(W, 1.05, 1.05, bone), ctl(F[f], 0.4, 0.4, bone) }, 2.4, 6.0, C.wingBone, M.Slate)
		spike("KanatUcu", group, bone, F[f], F[f] - W, V(0, -1, 0), 1.0, 0.45, 0.3, C.claw)
	end

	-- Zar üçgenleri: her köşe bir kemiğe bağlıdır; oyun sırasında her karede yeniden çizilir.
	local function Pt(bone, point)
		return { bone = bone, point = point }
	end
	local tris = {
		{ Pt("wingRoot" .. side, R), Pt("wingElbow" .. side, E), Pt("pelvis", B) },
		{ Pt("wingElbow" .. side, E), Pt("wingWrist" .. side, W), Pt("pelvis", B) },
		{ Pt("wingWrist" .. side, W), Pt("finger" .. side .. "4", F[4]), Pt("pelvis", B) },
		{ Pt("wingWrist" .. side, W), Pt("finger" .. side .. "3", F[3]), Pt("finger" .. side .. "4", F[4]) },
		{ Pt("wingWrist" .. side, W), Pt("finger" .. side .. "2", F[2]), Pt("finger" .. side .. "3", F[3]) },
		{ Pt("wingWrist" .. side, W), Pt("finger" .. side .. "1", F[1]), Pt("finger" .. side .. "2", F[2]) },
	}
	for _, tri in tris do
		table.insert(membranes, { group = group, side = side, points = tri })
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
for _, key in NECK_ORDER do
	local mouth = mouths[key]
	local out = Instance.new("Attachment")
	out.Name = "SimsekCikisi"
	out.CFrame = CFrame.new(0, 0, -mouth.Size.Z * 0.5)
	out.Parent = mouth
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "SimsekKivilcimi"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = seq({ { 0, RGB(255, 250, 200) }, { 1, RGB(255, 190, 40) } })
	sparks.Size = nums({ { 0, 0.8 }, { 1, 0 } })
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Rate = 70
	sparks.Speed = NumberRange.new(20, 34)
	sparks.SpreadAngle = Vector2.new(20, 20)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Enabled = false
	sparks:SetAttribute("SimsekEfekti", true)
	sparks.Parent = out
	local glow = Instance.new("PointLight")
	glow.Name = "AgizIsigi"
	glow.Color = RGB(255, 214, 100)
	glow.Range = 24
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = mouth
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
collider("GovdeCarpisma", CFrame.new(0, 14.5, 2.2) * CFrame.Angles(rad(-22), 0, 0), V(10, 15, 8.5))
collider("BacakCarpisma", CFrame.new(0, 5, 2.4), V(13, 10, 8))
collider("KuyrukCarpismaL", CFrame.new(3.6, 6, 19) * CFrame.Angles(rad(18), rad(14), 0), V(3.6, 3.6, 25))
collider("KuyrukCarpismaR", CFrame.new(-4.2, 6.6, 18.4) * CFrame.Angles(rad(16), rad(-16), 0), V(3.6, 3.6, 24))

-- ═════════════════════════════ RIG VERİSİ ═════════════════════════════
local function fmt(n: number): string
	local s = string.format("%.5f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
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

-- Zar parçaları: dinlenme pozunda çizilir; veriye köşe noktaları kemiğe göre yazılır.
local rigSource = fs.readFile("src/rig.luau")
local MEMBRANE_THICKNESS = 0.24
local triangle
do
	local env = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, membranes = {}, bolts = {} } }
	triangle = luau.load(rigSource, { debugName = "rig", environment = env })().triangle
end
table.insert(lines, "Rig.membranes = {")
for i, m in membranes do
	local world, pts = {}, {}
	for k, pt in m.points do
		world[k] = pt.point
		table.insert(pts, string.format("{ bone = %d, pos = %s }", boneIndex[pt.bone], v3(pt.point - pivotOf(pt.bone))))
	end
	local cf0, s0, cf1, s1 = triangle(world[1], world[2], world[3])
	assert(cf0, "dejenere zar üçgeni")
	local nameA, nameB = "Zar" .. m.side .. i .. "a", "Zar" .. m.side .. i .. "b"
	for _, pair in { { nameA, cf0, s0 }, { nameB, cf1, s1 } } do
		local w = Instance.new("WedgePart")
		w.Name = pair[1]
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.Size = V(MEMBRANE_THICKNESS, pair[3].Y, pair[3].Z)
		w.CFrame = pair[2]
		w.Color = C.membrane
		w.Material = M.SmoothPlastic
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = folder(m.group)
	end
	table.insert(lines, string.format("\t{ a = %q, b = %q, thickness = %s, points = { %s } },", nameA, nameB, fmt(MEMBRANE_THICKNESS), table.concat(pts, ", ")))
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "Rig.bolts = {")
for _, b in bolts do
	local quoted = {}
	for _, name in b.parts do
		table.insert(quoted, string.format("%q", name))
	end
	table.insert(lines, string.format("\t{ bone = %d, origin = %s, forward = %s, parts = { %s } },",
		boneIndex[b.bone], v3(b.origin - pivotOf(b.bone)), v3(b.forward), table.concat(quoted, ", ")))
end
table.insert(lines, "}")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "UcBasliRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("UcBasliEjderha.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("UcBasliEjderha.rbxmx yazıldı: %d parça, %d kemik, %d zar üçgeni, %d şimşek", count, #bones, #membranes, #bolts))
for name, f in folders do
	print(string.format("  %-12s %d", name, #f:GetChildren()))
end
