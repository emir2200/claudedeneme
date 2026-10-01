--[[
	Orman Örümceği modelini üretir: lune run src/build.luau   (orumcek/ klasöründen)
	Çıktı: OrmanOrumcegi.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Gövde parçaları kemiklere, bacak parçaları bacağın üst ya da alt bölümüne bağlıdır.
	Bacak bölümlerinin çerçeveleri oyunda ters kinematikle hesaplanır; parçaların bu
	çerçevelere göre konumları "OrumcekRig" ModuleScript'ine veri olarak yazılır.
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
local TAU = math.pi * 2

-- Tekrarlanabilir rastgelelik (Park–Miller): her derlemede aynı desen çıkar.
local seed = 6060606
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (görseldeki yaprak yeşili karın, koyu yeşil desen, parlayan gözler) ───
local RGB = Color3.fromRGB
local C = {
	abdomen = RGB(98, 162, 40),
	pattern = RGB(34, 82, 24),
	body = RGB(72, 134, 34),
	leg = RGB(80, 142, 40),
	band = RGB(38, 84, 24),
	tip = RGB(28, 48, 20),
	fang = RGB(34, 26, 18),
	eyeGreen = RGB(130, 255, 90),
	eyeRed = RGB(210, 32, 22),
	venom = RGB(150, 255, 80),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "OrmanOrumcegi"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 13)
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

--- Diş/kıl: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
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

--- Kontrol noktaları ({ pos, w, h, bone }) boyunca yay uzunluğuyla örnekleyici.
local function chainSampler(controls)
	local samples = {}
	for i = 1, #controls - 1 do
		local c0, c1 = controls[i], controls[i + 1]
		local seg = c1.pos - c0.pos
		local n = math.max(1, math.ceil(seg.Magnitude / 0.25))
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

--- Zincirin `s` noktasındaki yönü ve eksene dik iki birim vektör (yan ≈ X, normal = yön × yan).
local function chainFrame(sampler, s)
	local dir = (sampler.at(s + 0.4).pos - sampler.at(s - 0.4).pos).Unit
	local x = V(1, 0, 0)
	local side = (x - dir * x:Dot(dir)).Unit
	return dir, side, dir:Cross(side).Unit
end

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir gövde.
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

--- Gövdenin yüzeyine koyu desen çizgileri ağı çizer (görseldeki altıgen plakalar). Yüzey (yay
--- uzunluğu s, çevre açısı φ) ile parametrelenir; titretilmiş bir ızgaranın üçgenlerinin ağırlık
--- merkezleri komşu üçgenlerle birleştirilerek düzensiz çokgen hücreler elde edilir.
local function patternNet(group, surfaceParts, controls, opts)
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
			local ju = if i > 0 and i < nu then jitter(0.28) else 0
			local jv = if wrap or (j > 0 and j < nv) then jitter(0.28) else 0
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
		if #pair == 2 and rand() >= (opts.drop or 0.06) then
			local a, b = centroids[pair[1]], centroids[pair[2]]
			local pa, ra, da = surfacePoint(a.u, a.v)
			local pb, rb, db = surfacePoint(b.u, b.v)
			local len = (pb - pa).Magnitude
			if da > 0 and db > 0 and len > 0.25 then
				local normal = (ra + rb).Unit
				local bone = sampler.at(lerp(sFrom, sTo, (a.u + b.u) / 2 / nu)).bone
				ellipsoid("Desen", group, bone, lookFrame((pa + pb) / 2 + normal * 0.04, pb - pa, normal),
					V(opts.width or 0.32, opts.depth or 0.34, len * 1.25), C.pattern, M.SmoothPlastic, { shadow = false, query = false })
				count += 1
			end
		end
	end
	return count
end

local function ctl(pos, w, h, bone)
	return { pos = pos, w = w, h = h, bone = bone }
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
local CEPHALO = V(0, 6.4, -2.4)
addBone("govde", nil, CEPHALO)
addBone("karin", "govde", V(0, 7.2, 0.6))
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	addBone("kiskac" .. side, "govde", V(s * 0.75, 5.6, -5.4))
	addBone("palp" .. side, "govde", V(s * 1.4, 5.5, -5.0))
end

-- ═════════════════════════════ GÖVDE VE KARIN ═════════════════════════════
local headChain = {
	ctl(V(0, 6.6, 0.9), 3.4, 2.6, "govde"),
	ctl(V(0, 6.8, -1.2), 5.8, 3.6, "govde"),
	ctl(V(0, 6.6, -3.4), 6.0, 3.6, "govde"),
	ctl(V(0, 6.2, -5.0), 4.4, 2.8, "govde"),
	ctl(V(0, 5.8, -5.9), 2.8, 1.8, "govde"),
}
local headParts = smoothTube("Govde", "Govde", headChain, 1.0, 4.0, C.body, M.Slate)
ellipsoid("Bel", "Govde", "karin", CFrame.new(0, 7.1, 1.0), V(1.8, 1.6, 2.0), C.band, M.Slate)

-- Karın: arkaya doğru hafifçe yükselen, yumurta biçimli büyük gövde
local abdomenChain = {}
do
	local from, to = V(0, 7.5, 1.3), V(0, 10.0, 11.2)
	for _, k in { { 0, 3.4 }, { 0.12, 7.8 }, { 0.28, 9.8 }, { 0.45, 10.4 }, { 0.62, 10.0 }, { 0.78, 8.4 }, { 0.92, 5.0 }, { 1.0, 1.8 } } do
		table.insert(abdomenChain, ctl(lerp(from, to, k[1]), k[2], k[2] * 0.9, "karin"))
	end
end
local abdomenParts = smoothTube("Karin", "Karin", abdomenChain, 1.0, 5.0, C.abdomen, M.SmoothPlastic, { reflectance = 0.08 })
local patternCount = patternNet("Karin", abdomenParts, abdomenChain, { from = 0.6, to = chainSampler(abdomenChain).total - 0.6, cell = 2.7 })
patternCount += patternNet("Govde", headParts, headChain, { from = 0.8, to = chainSampler(headChain).total - 1.4, phiFrom = math.pi * 1.0, phiTo = math.pi * 2.0, cell = 2.2, width = 0.24, depth = 0.26 })
-- ağ memecikleri
for _, x in { 0.35, -0.35 } do
	spike("AgMemesi", "Karin", "karin", V(x, 9.9, 10.6), V(x, -0.3, 1), V(0, -1, 0), 0.9, 0.5, 0.35, C.band)
end

-- ═════════════════════════════ BAŞ: GÖZLER, ZEHİR DİŞLERİ, PALPLER ═════════════════════════════
local headSampler = chainSampler(headChain)
local function headSurface(s, dir)
	local origin = headSampler.at(s).pos
	return origin + dir * surfaceDistance(headParts, origin, dir)
end
local headTotal = headSampler.total
local greenEyes = {}
for _, s in { 1, -1 } do
	-- önde iki iri, parlayan yeşil göz
	local pos = headSurface(headTotal - 1.4, V(s * 0.55, 0.3, -1).Unit)
	table.insert(greenEyes, ellipsoid("Goz", "Govde", "govde", lookFrame(pos, V(s * 0.45, 0.2, -1), V(0, 1, 0)), V(0.9, 0.75, 0.55), C.eyeGreen, M.Neon, { shadow = false }))
	-- üstte küçük kırmızı gözler
	for _, d in { V(s * 0.35, 1, -0.45), V(s * 0.9, 0.8, -0.2) } do
		local p = headSurface(headTotal - 2.4, d.Unit)
		ellipsoid("KirmiziGoz", "Govde", "govde", CFrame.new(p), V(0.42, 0.36, 0.42), C.eyeRed, M.Neon, { shadow = false })
	end
end
local fangTips = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local bone = "kiskac" .. side
	local top = pivotOf(bone)
	local bottom = V(s * 0.8, 3.8, -6.0)
	local holder = segment("Kiskac", "Govde", bone, top, bottom, 1.2, 1.1, C.body, M.Slate, { extend = 1.15 })
	ellipsoid("KiskacBandi", "Govde", bone, lookFrame(lerp(top, bottom, 0.55), bottom - top), V(1.3, 1.2, 0.3), C.band, M.Slate)
	-- kıvrık zehir dişi: aşağı, sonra içe doğru iki kademe
	spike("ZehirDisi", "Govde", bone, bottom + V(0, 0.2, 0), V(-s * 0.25, -1, -0.15), V(-s, 0, 0), 1.0, 0.5, 0.35, C.fang)
	local tip = bottom + V(-s * 0.25, -0.85, -0.15)
	spike("ZehirDisi", "Govde", bone, tip, V(-s * 0.9, -0.6, 0), V(-s, 0, 0), 0.7, 0.32, 0.28, C.fang)
	table.insert(fangTips, { holder = holder, pos = tip + V(-s * 0.55, -0.35, 0) })
	-- palpler: önde iki kısa dokunaç
	local pb = "palp" .. side
	local p0, p1, p2 = pivotOf(pb), V(s * 2.4, 4.9, -6.6), V(s * 2.2, 3.4, -7.4)
	segment("Palp", "Govde", pb, p0, p1, 0.75, 0.75, C.leg, M.Slate)
	segment("Palp", "Govde", pb, p1, p2, 0.6, 0.6, C.leg, M.Slate)
	ellipsoid("PalpUcu", "Govde", pb, CFrame.new(p2), V(0.55, 0.55, 0.55), C.tip, M.Slate)
end

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
-- Bacak bölümlerinin dinlenme çerçeveleri, oyundaki ters kinematikle aynı işlevle hesaplanır.
local rigSource = fs.readFile("src/rig.luau")
local RigCode = luau.load(rigSource, { debugName = "rig", environment = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, legs = {} } } })()

local LEG_ANGLES = { 35, 68, 108, 145 }
local LEG_REACH = { 18.5, 17.0, 16.5, 18.0 }
local KNEE_HEIGHT = { 6.8, 6.4, 6.0, 6.4 }
local legs = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	for k = 1, 4 do
		local a = rad(LEG_ANGLES[k])
		local outward = V(s * math.sin(a), 0, -math.cos(a))
		local hip = CEPHALO + outward * 2.5 + V(0, -0.3, 0)
		local knee = hip + outward * 7.0 + V(0, KNEE_HEIGHT[k], 0)
		local foot = V(CEPHALO.X, 0.05, CEPHALO.Z) + outward * LEG_REACH[k]
		local l1, l2 = (knee - hip).Magnitude, (foot - knee).Magnitude
		local upperCF, lowerCF = RigCode.legFrames(hip, foot, V(0, 1, 0) + outward * 0.15, l1, l2)
		local group = "Bacak" .. side .. k
		local leg = { side = s, order = k, hip = hip, foot = foot, outward = outward, l1 = l1, l2 = l2, upper = {}, lower = {} }

		local function add(list, frame, part)
			table.insert(list, { name = part.Name, offset = frame:Inverse() * part.CFrame })
		end
		local function piece(list, frame, prefix, localCF, size, color)
			add(list, frame, ellipsoid(prefix, group, nil, frame * localCF, size, color, M.Slate))
		end
		local function bristle(list, frame, z, len)
			local out = frame:VectorToWorldSpace(V(jitter(0.4), 1, 0.5))
			local pos = frame * V(0, 0.45, -z)
			add(list, frame, spike("Kil", group, nil, pos, out, frame:VectorToWorldSpace(V(0, 0, 1)), len, 0.25, 0.12, C.tip, M.Slate, { shadow = false, query = false }))
		end
		-- üst bölüm (uyluk): kalın, iki koyu bant, dizde eklem
		piece(leg.upper, upperCF, "Uyluk", CFrame.new(0, 0, -l1 * 0.5), V(1.35, 1.35, l1 * 1.06), C.leg)
		for _, f in { 0.3, 0.62 } do
			piece(leg.upper, upperCF, "Bant", CFrame.new(0, 0, -l1 * f), V(1.5, 1.5, 0.3), C.band)
		end
		piece(leg.upper, upperCF, "Diz", CFrame.new(0, 0, -l1), V(1.55, 1.55, 1.55), C.band)
		bristle(leg.upper, upperCF, l1 * 0.45, 0.8)
		bristle(leg.upper, upperCF, l1 * 0.8, 0.7)
		-- alt bölüm: kaval, ince tarak ve koyu sivri uç; aralarda bantlar
		piece(leg.lower, lowerCF, "Kaval", CFrame.new(0, 0, -l2 * 0.28), V(1.15, 1.15, l2 * 0.6), C.leg)
		piece(leg.lower, lowerCF, "Tarak", CFrame.new(0, 0, -l2 * 0.74), V(0.8, 0.8, l2 * 0.42), C.leg)
		piece(leg.lower, lowerCF, "Uc", CFrame.new(0, 0, -l2 * 0.95), V(0.5, 0.5, l2 * 0.14), C.tip)
		for i, f in { 0.12, 0.3, 0.5, 0.66 } do
			local w = if i <= 2 then 1.25 else 0.92
			piece(leg.lower, lowerCF, "Bant", CFrame.new(0, 0, -l2 * f), V(w, w, 0.26), C.band)
		end
		bristle(leg.lower, lowerCF, l2 * 0.2, 0.7)
		bristle(leg.lower, lowerCF, l2 * 0.42, 0.6)
		table.insert(legs, leg)
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
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local VENOM = seq({ { 0, RGB(200, 255, 140) }, { 1, RGB(90, 200, 40) } })

-- gözlerin yeşil ışığı
local eyeLight = Instance.new("PointLight")
eyeLight.Name = "GozIsigi"
eyeLight.Color = RGB(120, 255, 90)
eyeLight.Range = 14
eyeLight.Brightness = 1.2
eyeLight.Shadows = false
eyeLight.Parent = greenEyes[1]

-- zehir dişlerinin ucundan arada bir damlayan zehir
for _, tip in fangTips do
	local a = attachment(tip.holder, "ZehirUcu", tip.holder.CFrame:Inverse() * CFrame.new(tip.pos))
	emitter(a, "ZehirDamlasi", {
		Texture = SPARKLE, Color = VENOM, LightEmission = 0.7, LightInfluence = 0.3, Size = nums({ { 0, 0.35 }, { 1, 0.25 } }),
		Lifetime = NumberRange.new(0.6, 0.7), Rate = 0.8, Speed = NumberRange.new(0, 0), Acceleration = V(0, -30, 0),
	})
end
-- saldırıda dişlerin arasından püsküren zehir sisi ve damlacıkları
local mouthPart = headParts[#headParts]
local spray = attachment(mouthPart, "ZehirCikisi", mouthPart.CFrame:Inverse() * CFrame.new(0, 4.6, -6.6) * CFrame.Angles(rad(-25), 0, 0))
emitter(spray, "ZehirSisi", {
	Texture = SMOKE, Color = seq({ { 0, RGB(170, 255, 110) }, { 1, RGB(70, 140, 40) } }), LightEmission = 0.4, LightInfluence = 0.4,
	Size = nums({ { 0, 1 }, { 0.6, 4.5 }, { 1, 7 } }), Transparency = nums({ { 0, 0.3 }, { 0.7, 0.55 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.8, 1.1), Rate = 70, Speed = NumberRange.new(22, 30), SpreadAngle = Vector2.new(14, 14),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), Drag = 1.4, Acceleration = V(0, -3, 0),
	EmissionDirection = Enum.NormalId.Front, Enabled = false, attributes = { Zehir = true },
})
emitter(spray, "ZehirDamlaciklari", {
	Texture = SPARKLE, Color = VENOM, LightEmission = 0.8, LightInfluence = 0.2, Size = nums({ { 0, 0.6 }, { 1, 0.3 } }),
	Lifetime = NumberRange.new(0.7, 1.0), Rate = 90, Speed = NumberRange.new(26, 36), SpreadAngle = Vector2.new(10, 10),
	Acceleration = V(0, -25, 0), EmissionDirection = Enum.NormalId.Front, Enabled = false, attributes = { Zehir = true },
})
-- karnın çevresinde süzülen yeşil sporlar
emitter(abdomenParts[math.ceil(#abdomenParts / 2)], "Spor", {
	Texture = SPARKLE, Color = seq({ { 0, RGB(210, 255, 120) }, { 1, RGB(120, 220, 60) } }), LightEmission = 0.7, LightInfluence = 0.3,
	Size = nums({ { 0, 0.25 }, { 0.5, 0.35 }, { 1, 0 } }), Lifetime = NumberRange.new(4, 6), Rate = 5, Speed = NumberRange.new(0.5, 1.5),
	SpreadAngle = Vector2.new(180, 180), Acceleration = V(0, 0.4, 0), Rotation = NumberRange.new(0, 360),
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
body.Size = V(10, 9, 17)
body.CFrame = CFrame.new(0, 8.2, 2.2) * CFrame.Angles(rad(-8), 0, 0)
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
local function pieceList(list)
	local out = {}
	for _, p in list do
		table.insert(out, string.format("{ name = %q, offset = %s }", p.name, cfLiteral(p.offset)))
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
-- Bacaklar: kalça gövde kemiğine göre, ayak model uzayında; parçalar bacak bölümlerine göre.
table.insert(lines, "Rig.legs = {")
for _, leg in legs do
	table.insert(lines, string.format("\t{ side = %d, order = %d, bone = %d, hip = %s, foot = %s, outward = %s, l1 = %s, l2 = %s,",
		leg.side, leg.order, boneIndex.govde, v3(leg.hip - CEPHALO), v3(leg.foot), v3(leg.outward), fmt(leg.l1), fmt(leg.l2)))
	table.insert(lines, "\t\tupper = { " .. pieceList(leg.upper) .. " },")
	table.insert(lines, "\t\tlower = { " .. pieceList(leg.lower) .. " } },")
end
table.insert(lines, "}")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "OrumcekRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("OrmanOrumcegi.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("OrmanOrumcegi.rbxmx yazıldı: %d parça (%d desen çizgisi), %d kemik, %d bacak", count, patternCount, #bones, #legs))
for name, f in folders do
	print(string.format("  %-10s %d", name, #f:GetChildren()))
end
