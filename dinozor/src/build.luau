--[[
	Lav Dinozoru modelini üretir: lune run src/build.luau   (dinozor/ klasöründen)
	Çıktı: LavDinozoru.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Her parça bir kemiğe bağlanır; parçaların kemiğe göre konumları, lav çatlaklarının
	parıltı grupları ve damlayan lav verisi "DinozorRig" ModuleScript'ine veri olarak yazılır.
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
local TAU = math.pi * 2

-- Tekrarlanabilir rastgelelik (Park–Miller): her derlemede aynı çatlak deseni çıkar.
local seed = 20260929
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (görseldeki kömür karası kabuk, turuncu lav, gri pençeler) ───
local RGB = Color3.fromRGB
local C = {
	crust = RGB(40, 33, 31),
	crustDark = RGB(26, 22, 21),
	glow = RGB(255, 110, 20),
	claw = RGB(150, 146, 140),
	tooth = RGB(176, 162, 146),
	eye = RGB(255, 176, 40),
	pupil = RGB(20, 8, 4),
	nostril = RGB(12, 10, 10),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "LavDinozoru"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 12)
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

-- Lav nabzı göğüsteki "kalpten" dışa doğru yayılır: her parlayan parçanın gecikmesi (sn).
local HEART = V(0, 13.2, -4.5)
local function phaseAt(pos): number
	return (pos - HEART).Magnitude * 0.045
end

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
	p.Parent = folder(group)
	if bone then
		table.insert(rigParts, { name = p.Name, bone = bone, cf = cf })
	end
	if opts.glow then
		table.insert(glowParts, { name = p.Name, phase = phaseAt(cf.Position) })
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

--- Diken/pençe/diş: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
local function spike(prefix, group, bone, pos, out, back, height, length, thickness, color, material, opts)
	out = out.Unit
	back = (back - out * back:Dot(out)).Unit
	local right = out:Cross(back).Unit
	local cf = CFrame.fromMatrix(pos + out * (height / 2), right, out, back)
	return basePart("WedgePart", prefix, group, bone, cf, V(thickness, height, length), color, material or M.Basalt, opts)
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

--- Zincirin `s` noktasındaki yönü ve eksene dik iki birim vektör (yan ≈ X, normal = yön × yan).
local function chainFrame(sampler, s)
	local dir = (sampler.at(s + 0.4).pos - sampler.at(s - 0.4).pos).Unit
	local x = V(1, 0, 0)
	local side = (x - dir * x:Dot(dir)).Unit
	return dir, side, dir:Cross(side).Unit
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

--- Bir borunun yüzeyine lav çatlağı ağı çizer. Yüzey (yay uzunluğu s, çevre açısı φ) ile
--- parametrelenir; titretilmiş bir ızgaranın üçgenlerinin ağırlık merkezleri komşu üçgenlerle
--- birleştirilir. Ortaya görseldeki gibi düzensiz çokgen kabuk parçaları ve aralarında lav çıkar.
local function crackNet(group, surfaceParts, controls, opts)
	local sampler = chainSampler(controls)
	local sFrom, sTo = opts.from or 0, opts.to or sampler.total
	local phiFrom, phiTo = opts.phiFrom or 0, opts.phiTo or TAU
	local wrap = phiTo - phiFrom >= TAU - 1e-6
	local cell = opts.cell or 3
	local radius = 0
	for k = 0, 8 do
		local c = sampler.at(lerp(sFrom, sTo, k / 8))
		radius += (c.w + c.h) / 4 / 9
	end
	local nu = math.max(1, math.floor((sTo - sFrom) / cell + 0.5))
	local nv = math.max(if wrap then 3 else 1, math.floor((phiTo - phiFrom) * radius / cell + 0.5))

	local verts = {}
	for i = 0, nu do
		verts[i] = {}
		for j = 0, if wrap then nv - 1 else nv do
			local ju = if i > 0 and i < nu then jitter(0.36) else 0
			local jv = if wrap or (j > 0 and j < nv) then jitter(0.36) else 0
			verts[i][j] = { u = i + ju, v = j + jv }
		end
	end
	local function corner(i, j)
		local jj = if wrap then j % nv else j
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
		local phi = lerp(phiFrom, phiTo, v / nv)
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
				local width = (opts.width or 0.42) * (0.55 + 0.9 * rand())
				ellipsoid("Catlak", group, bone, lookFrame((pa + pb) / 2 + normal * 0.05, pb - pa, normal),
					V(width, opts.depth or 0.5, len * 1.35), C.glow, M.Neon, { glow = true, shadow = false, query = false })
				count += 1
			end
		end
	end
	return count
end

--- Sırt dikenleri: her biri koyu bir kaya dikeni ve kenarlarından taşan ince, parlayan bir lav çizgisi.
local function dorsalRow(group, surfaceParts, controls, opts)
	local sampler = chainSampler(controls)
	local list = {}
	local s = opts.from
	while s <= opts.to do
		local c = sampler.at(s)
		local dir = chainFrame(sampler, s)
		local up = V(0, 1, 0)
		local dorsal = (up - dir * up:Dot(dir)).Unit
		local out = (dorsal + V(jitter(0.14), 0, 0)).Unit
		local base = c.pos + dorsal * (surfaceDistance(surfaceParts, c.pos, dorsal) - 0.4)
		local h = opts.heightAt(s) * (0.78 + 0.44 * rand())
		local back = dir * opts.towardTail
		local main = spike("Diken", group, c.bone, base, out, back, h, h * 0.72, 0.6, C.crust, M.Basalt)
		spike("DikenLav", group, c.bone, base - out * 0.05, out, back, h * 1.1, h * 0.72 * 1.1, 0.18, C.glow, M.Neon,
			{ glow = true, shadow = false, query = false })
		table.insert(list, { part = main, height = h, length = h * 0.72 })
		s += opts.spacing * (0.85 + 0.3 * rand())
	end
	return list
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

local function ctl(pos, w, h, bone)
	return { pos = pos, w = w, h = h, bone = bone }
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("pelvis", nil, V(0, 13.0, 3.0))
addBone("spine1", "pelvis", V(0, 13.4, -1.6))
addBone("chest", "spine1", V(0, 13.6, -5.8))
addBone("neck1", "chest", V(0, 14.6, -9.0))
addBone("neck2", "neck1", V(0, 15.8, -11.4))
addBone("head", "neck2", V(0, 16.6, -13.4))

local headFrame = CFrame.new(pivotOf("head")) * CFrame.Angles(rad(-4), 0, 0)
local function H(x, y, z) -- baş koordinatlarından dünyaya
	return headFrame * V(x, y, z)
end
local function HD(x, y, z) -- baş koordinatlarındaki bir yön
	return headFrame:VectorToWorldSpace(V(x, y, z))
end
local function HCF(x, y, z, rx, ry, rz)
	return headFrame * CFrame.new(x, y, z) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end
addBone("jaw", "head", H(0, -0.6, -0.6))

local tailPivots = { V(0, 13.6, 7.8), V(0, 13.0, 12.4), V(0, 12.0, 17.0), V(0, 10.4, 21.4), V(0, 8.4, 25.6), V(0, 6.4, 29.4), V(0, 4.6, 32.8) }
for i, p in tailPivots do
	addBone("tail" .. i, if i == 1 then "pelvis" else "tail" .. (i - 1), p)
end

for side, s in { L = 1, R = -1 } do
	addBone("thigh" .. side, "pelvis", V(s * 3.3, 12.0, 3.4))
	addBone("shin" .. side, "thigh" .. side, V(s * 4.3, 7.0, 0.2))
	addBone("foot" .. side, "shin" .. side, V(s * 4.1, 3.4, 3.8))
	addBone("arm" .. side, "chest", V(s * 2.4, 11.4, -7.4))
	addBone("forearm" .. side, "arm" .. side, V(s * 2.9, 9.8, -8.1))
	addBone("hand" .. side, "forearm" .. side, V(s * 2.8, 9.2, -9.5))
end

-- ═════════════════════════════ GÖVDE VE BOYUN ═════════════════════════════
-- Kalçanın arkasından başın içine uzanan zincir: { konum, genişlik, derinlik, kemik }
local bodyChain = {
	ctl(V(0, 13.8, 6.4), 6.4, 7.2, "pelvis"),
	ctl(V(0, 13.3, 2.6), 7.6, 9.0, "pelvis"),
	ctl(V(0, 12.9, -1.4), 8.2, 9.8, "spine1"),
	ctl(V(0, 13.2, -5.2), 7.2, 8.6, "chest"),
	ctl(V(0, 14.2, -8.4), 5.4, 6.4, "chest"),
	ctl(V(0, 15.3, -10.6), 4.5, 5.2, "neck1"),
	ctl(V(0, 16.2, -12.4), 4.1, 4.7, "neck2"),
	ctl(V(0, 16.9, -14.4), 3.7, 4.2, "neck2"),
}
local bodyParts = smoothTube("Govde", "Govde", bodyChain, 1.4, 7.0, C.crust, M.Basalt)
local bodySampler = chainSampler(bodyChain)

-- ═════════════════════════════ KUYRUK ═════════════════════════════
local tailChain = { ctl(V(0, 13.9, 3.0), 6.4, 7.0, "pelvis") }
local tailSizes = { { 5.8, 6.4 }, { 4.8, 5.4 }, { 3.9, 4.4 }, { 3.1, 3.5 }, { 2.4, 2.7 }, { 1.8, 2.0 }, { 1.3, 1.4 } }
for i, p in tailPivots do
	table.insert(tailChain, ctl(p, tailSizes[i][1], tailSizes[i][2], "tail" .. i))
end
table.insert(tailChain, ctl(V(0, 3.2, 36.0), 0.7, 0.7, "tail7"))
local tailParts = smoothTube("Kuyruk", "Kuyruk", tailChain, 1.5, 6.0, C.crust, M.Basalt)
local tailSampler = chainSampler(tailChain)

-- ═════════════════════════════ BAŞ ═════════════════════════════
local function hctl(x, y, z, w, h, bone)
	return ctl(H(x, y, z), w, h, bone or "head")
end
local headChain = {
	hctl(0, 0.9, 1.0, 3.6, 4.2),
	hctl(0, 1.0, -1.6, 4.4, 4.8),
	hctl(0, 0.7, -4.2, 3.6, 3.8),
	hctl(0, 0.4, -6.6, 2.9, 2.9),
	hctl(0, 0.2, -8.6, 2.4, 2.3),
	hctl(0, 0.1, -9.8, 1.8, 1.6),
}
local headParts = smoothTube("Kafa", "Kafa", headChain, 1.0, 3.6, C.crust, M.Basalt)
local jawChain = {
	hctl(0, -1.1, -0.2, 3.8, 2.4, "jaw"),
	hctl(0, -1.8, -3.0, 3.4, 2.0, "jaw"),
	hctl(0, -1.75, -6.0, 2.7, 1.6, "jaw"),
	hctl(0, -1.5, -8.4, 2.0, 1.3, "jaw"),
	hctl(0, -1.4, -9.3, 1.5, 1.0, "jaw"),
}
local jawParts = smoothTube("Cene", "Kafa", jawChain, 1.0, 3.4, C.crust, M.Basalt)

-- Ağız içi: üst damak ve alt çenedeki parlayan lav; alev buradan çıkar.
local mouth = ellipsoid("Agiz", "Kafa", "head", HCF(0, -0.95, -4.8), V(2.3, 0.9, 7.6), C.glow, M.Neon, { glow = true, shadow = false })
ellipsoid("AgizAlt", "Kafa", "jaw", HCF(0, -1.05, -4.6), V(2.1, 0.7, 7.0), C.glow, M.Neon, { glow = true, shadow = false })

for _, s in { 1, -1 } do
	-- çene kasları
	ellipsoid("Yanak", "Kafa", "head", HCF(s * 1.55, 0.0, -0.4), V(1.4, 2.8, 3.2), C.crust, M.Basalt)
	-- göz: yüzeye oturtulur, üstünde kaş çıkıntısı ve küçük boynuz
	local eyeOrigin = H(0, 1.3, -3.2)
	local eyeDir = HD(s, 0.35, 0).Unit
	local eyePos = eyeOrigin + eyeDir * (surfaceDistance(headParts, eyeOrigin, eyeDir) - 0.12)
	local eyeRot = headFrame.Rotation * CFrame.Angles(0, s * rad(15), 0)
	ellipsoid("Goz", "Kafa", "head", CFrame.new(eyePos) * eyeRot, V(0.4, 0.6, 0.9), C.eye, M.Neon, { shadow = false })
	ellipsoid("GozBebegi", "Kafa", "head", CFrame.new(eyePos + eyeDir * 0.16) * eyeRot, V(0.12, 0.5, 0.16), C.pupil, M.SmoothPlastic, { shadow = false })
	local browDir = HD(s * 0.75, 1, 0).Unit
	local browPos = eyeOrigin + browDir * (surfaceDistance(headParts, eyeOrigin, browDir) - 0.2)
	ellipsoid("Kas", "Kafa", "head", CFrame.new(browPos) * headFrame.Rotation * CFrame.Angles(0, 0, -s * rad(35)), V(1.3, 0.7, 2.4), C.crustDark, M.Basalt)
	spike("KasBoynuzu", "Kafa", "head", browPos + HD(0, 0.1, 0.8), HD(s * 0.3, 1, 0.2), HD(0, 0, 1), 0.9, 0.7, 0.4, C.crustDark)
	-- burun delikleri
	local noseOrigin = H(0, 0.2, -9.0)
	local noseDir = HD(s * 0.5, 1, 0).Unit
	ellipsoid("BurunDeligi", "Kafa", "head", CFrame.new(noseOrigin + noseDir * (surfaceDistance(headParts, noseOrigin, noseDir) - 0.05)) * headFrame.Rotation,
		V(0.45, 0.3, 0.6), C.nostril, M.SmoothPlastic, { shadow = false })
	-- üst dişler: dudak çizgisi boyunca aşağı bakar
	for i = 0, 7 do
		local z = -2.6 - i * 0.86
		local origin = H(0, 0.3, z)
		local dir = HD(s * 0.62, -1, 0).Unit
		local base = origin + dir * surfaceDistance(headParts, origin, dir) + HD(0, 0.15, 0)
		local size = if i >= 2 and i <= 5 then 1.0 else 0.7
		spike("Dis", "Kafa", "head", base, HD(0, -1, 0), HD(0, 0, -1), size * (0.85 + 0.3 * rand()), 0.42, 0.26, C.tooth, M.SmoothPlastic, { shadow = false })
	end
	-- alt dişler: yukarı bakar
	for i = 0, 6 do
		local z = -2.9 - i * 0.9
		local origin = H(0, -1.7, z)
		local dir = HD(s * 0.62, 1, 0).Unit
		local base = origin + dir * surfaceDistance(jawParts, origin, dir) - HD(0, 0.15, 0)
		spike("AltDis", "Kafa", "jaw", base, HD(0, 1, 0), HD(0, 0, -1), 0.75 * (0.85 + 0.3 * rand()), 0.38, 0.24, C.tooth, M.SmoothPlastic, { shadow = false })
	end
end

-- ═════════════════════════════ BACAKLAR VE KOLLAR ═════════════════════════════
local legCracks = 0
for side, s in { L = 1, R = -1 } do
	local hip, knee, ankle = pivotOf("thigh" .. side), pivotOf("shin" .. side), pivotOf("foot" .. side)
	local ball = V(s * 4.0, 0.9, 0.9)
	-- uyluk: kalın "but" kası
	local thighChain = { ctl(hip + V(0, 0.6, 0.4), 3.8, 4.2, "thigh" .. side), ctl(knee, 2.8, 3.0, "thigh" .. side) }
	local thighParts = smoothTube("Uyluk", "Bacaklar", thighChain, 1.4, 4.4, C.crust, M.Basalt)
	table.insert(thighParts, segment("UylukKasi", "Bacaklar", "thigh" .. side, hip + V(s * 0.5, 0.4, 1.0), knee + V(s * 0.2, 0.9, 1.2), 4.2, 5.2, C.crust, M.Basalt, { extend = 1.15 }))
	-- incik ve baldır
	local shinChain = { ctl(knee, 3.0, 3.2, "shin" .. side), ctl(ankle, 2.2, 2.3, "shin" .. side) }
	local shinParts = smoothTube("Incik", "Bacaklar", shinChain, 1.3, 4.0, C.crust, M.Basalt)
	table.insert(shinParts, segment("Baldir", "Bacaklar", "shin" .. side, knee + V(0, -0.4, 0.8), ankle + V(0, 1.2, 0.2), 3.0, 3.4, C.crust, M.Basalt, { extend = 1.0 }))
	-- ayak tarağı, taban ve parmaklar
	smoothTube("Ayak", "Bacaklar", { ctl(ankle, 2.2, 2.3, "foot" .. side), ctl(ball, 1.9, 1.6, "foot" .. side) }, 1.0, 3.0, C.crust, M.Basalt)
	ellipsoid("Taban", "Bacaklar", "foot" .. side, CFrame.new(ball + V(0, -0.15, -0.4)), V(3.3, 1.4, 3.0), C.crust, M.Basalt)
	for _, dx in { -1.0, 0, 1.0 } do
		local base = ball + V(s * dx * 0.9, -0.2, -0.6)
		local tip = V(ball.X + s * dx * 1.5, 0.5, ball.Z - 3.0 + math.abs(dx) * 0.5)
		segment("Parmak", "Bacaklar", "foot" .. side, base, tip, 1.2, 1.05, C.crust, M.Basalt)
		spike("Pence", "Bacaklar", "foot" .. side, tip + V(0, 0.05, -0.25), V(0, -0.25, -1), V(0, 1, 0), 1.5, 0.7, 0.5, C.claw, M.SmoothPlastic)
	end
	spike("Pence", "Bacaklar", "foot" .. side, ball + V(-s * 0.9, 0.2, 1.0), V(-s * 0.3, -0.5, 1), V(0, 1, 0), 0.7, 0.4, 0.3, C.claw, M.SmoothPlastic)
	legCracks += crackNet("Bacaklar", thighParts, thighChain, { cell = 2.6 })
	legCracks += crackNet("Bacaklar", shinParts, shinChain, { cell = 2.3, width = 0.34, depth = 0.4 })

	-- kısa ön kollar
	local shoulder, elbow, wrist = pivotOf("arm" .. side), pivotOf("forearm" .. side), pivotOf("hand" .. side)
	segment("Kol", "Kollar", "arm" .. side, shoulder, elbow, 1.4, 1.5, C.crust, M.Basalt)
	segment("Onkol", "Kollar", "forearm" .. side, elbow, wrist, 1.1, 1.1, C.crust, M.Basalt)
	ellipsoid("El", "Kollar", "hand" .. side, CFrame.new(wrist + V(0, -0.1, -0.3)), V(0.9, 0.7, 1.1), C.crust, M.Basalt)
	for _, dx in { -0.25, 0.25 } do
		local base = wrist + V(dx, -0.2, -0.6)
		local tip = base + V(dx * 0.4, -0.7, -0.6)
		segment("ElParmak", "Kollar", "hand" .. side, base, tip, 0.4, 0.4, C.crust, M.Basalt)
		spike("Pence", "Kollar", "hand" .. side, tip, V(0, -0.7, -0.5), V(0, 0.3, 1), 0.6, 0.3, 0.22, C.claw, M.SmoothPlastic)
	end
end

-- ═════════════════════════════ LAV ÇATLAKLARI ═════════════════════════════
local crackCount = legCracks
crackCount += crackNet("Govde", bodyParts, bodyChain, { from = 0.5, to = bodySampler.total - 1.8, cell = 3.2, width = 0.46, depth = 0.55 })
crackCount += crackNet("Kuyruk", tailParts, tailChain, { from = 2.5, to = tailSampler.total - 3.5, cell = 2.8 })
-- başın üstü ve yanları (ağız içi hariç), alt çenenin altı ve yanları
crackCount += crackNet("Kafa", headParts, headChain, { from = 1.2, to = chainSampler(headChain).total - 0.4, phiFrom = math.pi * 0.8, phiTo = math.pi * 2.2, cell = 2.2, width = 0.3, depth = 0.4 })
crackCount += crackNet("Kafa", jawParts, jawChain, { from = 0.6, to = chainSampler(jawChain).total - 0.5, phiFrom = -math.pi * 0.2, phiTo = math.pi * 1.2, cell = 1.9, width = 0.28, depth = 0.36 })

-- ═════════════════════════════ YANAN SIRT DİKENLERİ ═════════════════════════════
local backSpikes = dorsalRow("Govde", bodyParts, bodyChain, {
	from = 1.6,
	to = bodySampler.total - 1.4,
	spacing = 1.7,
	towardTail = -1,
	heightAt = profile({ { 0, 3.8 }, { 4, 4.4 }, { 8, 4.6 }, { 12, 4.0 }, { 15, 3.0 }, { 18, 2.0 }, { 21, 1.3 } }),
})
local tailSpikes = dorsalRow("Kuyruk", tailParts, tailChain, {
	from = 4.0,
	to = 24,
	spacing = 1.6,
	towardTail = 1,
	heightAt = profile({ { 4, 3.6 }, { 24, 0.9 } }),
})

-- ═════════════════════════════ DAMLAYAN LAV ═════════════════════════════
-- Damlalar oyunda her karede yeniden konumlanır: her zaman aşağı sarkar, uzar ve kopar.
local drips = {}
local function drip(sampler, parts, s, length, width)
	local c = sampler.at(s)
	local down = V(0, -1, 0)
	local anchor = c.pos + down * (surfaceDistance(parts, c.pos, down) - 0.25)
	local p = ellipsoid("Damla", "Damlalar", nil, CFrame.new(anchor + down * length * 0.35), V(width, length * 0.7, width), C.glow, M.Neon,
		{ glow = true, shadow = false, query = false })
	table.insert(drips, { name = p.Name, bone = c.bone, anchor = anchor, length = length, width = width, period = 2.2 + 1.4 * rand(), phase = rand() })
	return p, anchor
end
local dripSpots = {
	{ chainSampler(jawChain), jawParts, 3.2, 2.4, 0.42 },
	{ chainSampler(jawChain), jawParts, 6.6, 1.8, 0.36 },
	{ bodySampler, bodyParts, 16.8, 2.0, 0.4 },
	{ bodySampler, bodyParts, 6.2, 3.0, 0.5 },
	{ bodySampler, bodyParts, 9.8, 2.2, 0.44 },
	{ tailSampler, tailParts, 9.5, 1.8, 0.38 },
	{ tailSampler, tailParts, 15.5, 1.4, 0.32 },
}
local dripAnchors = {}
for _, d in dripSpots do
	local _, anchor = drip(d[1], d[2], d[3], d[4], d[5])
	table.insert(dripAnchors, anchor)
end

-- ═════════════════════════════ YERDEKİ LAV GÖLLERİ ═════════════════════════════
-- Ayakların dibinde ve damlaların düştüğü yerlerde; kemiğe bağlı değildir, modelle birlikte taşınır.
-- Her göl üst üste binen birkaç yassı elipsten oluşur, böylece kenarları düzensiz olur.
local function pool(center, size)
	local blobs = 2 + math.floor(rand() * 2)
	for k = 1, blobs do
		local offset = if k == 1 then V(0, 0, 0) else V(jitter(size * 0.35), 0, jitter(size * 0.3))
		local scaleK = if k == 1 then 1 else 0.45 + 0.3 * rand()
		local cf = CFrame.new(center.X + offset.X, 0.05 + k * 0.01, center.Z + offset.Z) * CFrame.Angles(0, rand() * math.pi, 0)
		ellipsoid("LavGolu", "LavGolleri", nil, cf, V(size * scaleK * (0.9 + 0.4 * rand()), 0.12, size * scaleK * (0.6 + 0.3 * rand())), C.glow, M.Neon,
			{ glow = true, shadow = false, query = false })
	end
	if size > 3 then
		local cf = CFrame.new(center.X + jitter(size * 0.2), 0.1, center.Z + jitter(size * 0.15)) * CFrame.Angles(0, rand() * math.pi, 0)
		ellipsoid("LavKabugu", "LavGolleri", nil, cf, V(size * 0.32, 0.16, size * 0.14), C.crustDark, M.Basalt, { shadow = false, query = false })
	end
end
pool(V(5.4, 0, -1.6), 4.6)
pool(V(-4.8, 0, -0.2), 4.0)
pool((dripAnchors[4] + dripAnchors[5]) / 2 + V(0.6, 0, 0), 3.6) -- karın damlaları
pool((dripAnchors[1] + dripAnchors[2]) / 2, 3.0) -- çene damlaları
pool(dripAnchors[3], 2.0) -- boyun damlası
pool(dripAnchors[6], 2.2) -- kuyruk damlaları
pool(dripAnchors[7], 1.6)

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
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE_COLORS = seq({ { 0, RGB(255, 246, 190) }, { 0.2, RGB(255, 190, 60) }, { 0.55, RGB(255, 90, 20) }, { 1, RGB(110, 20, 6) } })

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
local function light(parent, name, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Name = name
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Ağız: sürekli yanan küçük alevler; kükrerken alev, duman ve yere düşen lav damlaları püskürür.
local mouthOut = attachment(mouth, "AlevCikisi", CFrame.new(0, 0, -3.4))
emitter(mouth, "AgizAlevi", {
	Texture = FIRE, Color = FIRE_COLORS, LightEmission = 1, LightInfluence = 0,
	Size = nums({ { 0, 0.6 }, { 0.4, 1.4 }, { 1, 0.2 } }), Transparency = nums({ { 0, 0.3 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.4, 0.7), Rate = 14, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(30, 30),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), Acceleration = V(0, 7, 0),
	EmissionDirection = Enum.NormalId.Front, ZOffset = 0.5,
})
emitter(mouthOut, "Alev", {
	Texture = FIRE, Color = FIRE_COLORS, LightEmission = 1, LightInfluence = 0,
	Size = nums({ { 0, 1.2 }, { 0.4, 4.0 }, { 1, 7.0 } }), Transparency = nums({ { 0, 0.25 }, { 0.7, 0.45 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.6, 1.0), Rate = 170, Speed = NumberRange.new(34, 48), SpreadAngle = Vector2.new(10, 10),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120), Drag = 1.2, Acceleration = V(0, 6, 0),
	EmissionDirection = Enum.NormalId.Front, ZOffset = 1, Enabled = false, attributes = { AlevNefesi = true },
})
emitter(mouthOut, "AlevCekirdegi", {
	Texture = FIRE, Color = seq({ { 0, RGB(255, 255, 230) }, { 0.5, RGB(255, 220, 110) }, { 1, RGB(255, 120, 30) } }),
	LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.6 }, { 0.5, 2.2 }, { 1, 3.2 } }),
	Transparency = nums({ { 0, 0.1 }, { 0.8, 0.5 }, { 1, 1 } }), Lifetime = NumberRange.new(0.35, 0.55), Rate = 110,
	Speed = NumberRange.new(44, 58), SpreadAngle = Vector2.new(5, 5), Rotation = NumberRange.new(0, 360),
	EmissionDirection = Enum.NormalId.Front, ZOffset = 1.5, Enabled = false, attributes = { AlevNefesi = true },
})
emitter(mouthOut, "AlevDumani", {
	Texture = SMOKE, Color = seq({ { 0, RGB(80, 64, 56) }, { 1, RGB(30, 28, 27) } }), LightInfluence = 0.5,
	Size = nums({ { 0, 2 }, { 1, 9 } }), Transparency = nums({ { 0, 0.5 }, { 1, 1 } }), Lifetime = NumberRange.new(1.4, 2.2),
	Rate = 20, Speed = NumberRange.new(18, 28), SpreadAngle = Vector2.new(14, 14), Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-30, 30), Drag = 1.5, Acceleration = V(0, 5, 0), EmissionDirection = Enum.NormalId.Front,
	Enabled = false, attributes = { AlevNefesi = true },
})
emitter(mouthOut, "LavTukurugu", {
	Texture = FIRE, Color = seq({ { 0, RGB(255, 220, 120) }, { 1, RGB(255, 80, 10) } }), LightEmission = 1, LightInfluence = 0,
	Size = nums({ { 0, 0.7 }, { 1, 0.4 } }), Lifetime = NumberRange.new(1.0, 1.4), Rate = 35, Speed = NumberRange.new(18, 30),
	SpreadAngle = Vector2.new(18, 18), Acceleration = V(0, -55, 0), EmissionDirection = Enum.NormalId.Front,
	Enabled = false, attributes = { AlevNefesi = true },
})
light(mouth, "AgizIsigi", RGB(255, 130, 40), 22, 1)

-- Sırt: uzun dikenlerin tepesinde alevler, birkaç yerden yükselen kara duman ve kıvılcımlar.
local allSpikes = {}
for _, d in backSpikes do
	table.insert(allSpikes, d)
end
for _, d in tailSpikes do
	table.insert(allSpikes, d)
end
local flameCount, tallest = 0, allSpikes[1]
for i, d in allSpikes do
	if d.height > tallest.height then
		tallest = d
	end
	local tip = attachment(d.part, "Uc", CFrame.new(0, d.height / 2 - 0.3, d.length / 2 - 0.3))
	if d.height > 2.4 and i % 2 == 1 then
		flameCount += 1
		emitter(tip, "SirtAlevi", {
			Texture = FIRE, Color = FIRE_COLORS, LightEmission = 1, LightInfluence = 0,
			Size = nums({ { 0, 1.4 }, { 0.3, 2.6 }, { 1, 0.4 } }), Transparency = nums({ { 0, 0.2 }, { 0.8, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.9), Rate = 16, Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(15, 15),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), Acceleration = V(0, 9, 0),
			EmissionDirection = Enum.NormalId.Top, ZOffset = 0.5, attributes = { SirtAlevi = true, TemelHiz = 16 },
		})
	end
	if i == 4 or i == 9 or i == #backSpikes + 3 then
		emitter(tip, "SirtDumani", {
			Texture = SMOKE, Color = seq({ { 0, RGB(52, 44, 40) }, { 1, RGB(22, 20, 20) } }), LightInfluence = 0.6,
			Size = nums({ { 0, 2.5 }, { 1, 10 } }), Transparency = nums({ { 0, 0.35 }, { 1, 1 } }),
			Lifetime = NumberRange.new(3, 4.5), Rate = 5, Speed = NumberRange.new(4, 7), SpreadAngle = Vector2.new(20, 20),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20), Drag = 0.4, Acceleration = V(0, 3, 2),
			EmissionDirection = Enum.NormalId.Top, attributes = { SirtAlevi = true, TemelHiz = 5 },
		})
	end
	if i == 6 or i == #backSpikes + 1 then
		emitter(tip, "Kivilcim", {
			Texture = SPARKLE, Color = seq({ { 0, RGB(255, 210, 90) }, { 1, RGB(255, 80, 20) } }), LightEmission = 1, LightInfluence = 0,
			Size = nums({ { 0, 0.35 }, { 1, 0 } }), Lifetime = NumberRange.new(1.5, 2.8), Rate = 9, Speed = NumberRange.new(3, 7),
			SpreadAngle = Vector2.new(40, 40), Acceleration = V(0, 4, 1), EmissionDirection = Enum.NormalId.Top,
			attributes = { SirtAlevi = true, TemelHiz = 9 },
		})
	end
end
light(tallest.part, "SirtIsigi", RGB(255, 120, 30), 24, 1.6)

-- Gövdenin altındaki parıltı (bacakları ve yeri aydınlatır)
local bellyPart = bodyParts[1]
for _, p in bodyParts do
	if (p.CFrame.Position - V(0, 11, -3)).Magnitude < (bellyPart.CFrame.Position - V(0, 11, -3)).Magnitude then
		bellyPart = p
	end
end
light(bellyPart, "GovdeIsigi", RGB(255, 110, 30), 18, 1)

-- Damlaların ucundan kopan lav damlası (animasyon script'i koptuğu anda tek tek yayar).
for _, d in drips do
	local part = folders["Damlalar"]:FindFirstChild(d.name)
	local tip = attachment(part, "DamlaUcu", CFrame.new(0, -part.Size.Y / 2, 0))
	local fallTime = math.sqrt(2 * d.anchor.Y / 50) -- yere çarpınca kaybolsun
	emitter(tip, "Damla", {
		Texture = FIRE, Color = seq({ { 0, RGB(255, 200, 90) }, { 1, RGB(255, 90, 15) } }), LightEmission = 1, LightInfluence = 0,
		Size = nums({ { 0, 0.55 }, { 1, 0.4 } }), Lifetime = NumberRange.new(fallTime, fallTime), Rate = 0, Speed = NumberRange.new(0, 0),
		Acceleration = V(0, -50, 0), EmissionDirection = Enum.NormalId.Bottom,
	})
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
collider("GovdeCarpisma", CFrame.new(0, 13.4, -2.5), V(8.4, 9.6, 17))
collider("BasCarpisma", CFrame.new(0, 16.4, -19), V(4.6, 5.4, 11))
collider("BacakCarpisma", CFrame.new(0, 4.8, 1.2), V(11, 9.6, 7.5))
collider("KuyrukCarpisma", CFrame.new(0, 9.2, 21) * CFrame.Angles(rad(22), 0, 0), V(4.4, 4.4, 27))

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

-- Parlayan parçalar nabız gecikmesine göre gruplanır (0.25 sn'lik dilimler).
local groups, groupList = {}, {}
for _, g in glowParts do
	local key = math.floor(g.phase / 0.25 + 0.5)
	if not groups[key] then
		groups[key] = {}
		table.insert(groupList, key)
	end
	table.insert(groups[key], string.format("%q", g.name))
end
table.sort(groupList)
table.insert(lines, "Rig.glowGroups = {")
for _, key in groupList do
	table.insert(lines, string.format("\t{ phase = %s, parts = { %s } },", fmt(key * 0.25), table.concat(groups[key], ", ")))
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "Rig.drips = {")
for _, d in drips do
	table.insert(lines, string.format("\t{ name = %q, bone = %d, anchor = %s, length = %s, width = %s, period = %s, phase = %s },",
		d.name, boneIndex[d.bone], v3(d.anchor - pivotOf(d.bone)), fmt(d.length), fmt(d.width), fmt(d.period), fmt(d.phase)))
end
table.insert(lines, "}")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "DinozorRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. fs.readFile("src/rig.luau")
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("LavDinozoru.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("LavDinozoru.rbxmx yazıldı: %d parça (%d lav çatlağı), %d kemik, %d diken, %d sırt alevi, %d damla, %d parıltı grubu",
	count, crackCount, #bones, #allSpikes, flameCount, #drips, #groupList))
