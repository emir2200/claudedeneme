--[[
	Zırhlı Gergedan modelini üretir: lune run src/build.luau   (gergedan/ klasöründen)
	Çıktı: ZirhliGergedan.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Koyu gri bir gergedan gövdesi, sırtında ve böğürlerinde kırık zırh kıymıkları, altın gibi
	parlayan boynuz uçları, ateşli bir ağız ve gövdeye serpilmiş kor zerreleri. Gövde, baş,
	kulaklar ve kuyruk kemiklere; bacak parçaları bacak bölümlerine bağlıdır ve
	"GergedanRig" ModuleScript'ine veri olarak yazılır.
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
local seed = 1010101
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function jitter(amount: number): number
	return (rand() * 2 - 1) * amount
end

-- ─── Renkler (koyu gri deri, kırık zırh, altın parıltı, ateşli ağız) ───
local RGB = Color3.fromRGB
local SHARDS = { RGB(74, 76, 82), RGB(88, 90, 96), RGB(62, 64, 70), RGB(102, 104, 110) }
local C = {
	skin = RGB(64, 64, 70),
	skinDark = RGB(48, 48, 54),
	fold = RGB(56, 56, 62),
	glow = RGB(255, 150, 40),
	gold = RGB(255, 196, 80),
	hornBase = RGB(58, 56, 56),
	hornMid = RGB(132, 104, 62),
	nail = RGB(40, 38, 40),
	eye = RGB(26, 20, 16),
	ridge = RGB(170, 152, 92),
	nostril = RGB(20, 18, 20),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "ZirhliGergedan"
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

-- Işıltı nabzı göğüsten dışa doğru yayılır: her parlayan parçanın gecikmesi (sn).
local HEART = V(0, 7.6, -1.5)

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
	p.Material = material or M.Slate
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
	if opts.glow then
		table.insert(glowParts, { name = p.Name, phase = (cf.Position - HEART).Magnitude * 0.04 })
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

--- a ile b arasına gerilmiş elips.
local function segment(prefix, group, bone, a, b, w, h, color, material, opts)
	opts = opts or {}
	local len = (b - a).Magnitude * (opts.extend or 1.2)
	return ellipsoid(prefix, group, bone, lookFrame((a + b) / 2, b - a, opts.up), V(w, h, len), color, material, opts)
end

--- Diken/tırnak: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
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

--- Üçgen kıymık: tabanı `base`te `width` genişliğinde, ucu `tip`te; düz yüzü `normal`e bakan iki WedgePart.
local function triangle(prefix, group, bone, base, tip, width, normal, thickness, color, material, opts)
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
	basePart("WedgePart", prefix, group, bone, CFrame.fromMatrix((a + b) / 2, right, up, back), V(thickness, height, math.abs(ab:Dot(back))), color, material, opts)
	basePart("WedgePart", prefix, group, bone, CFrame.fromMatrix((a + c) / 2, -right, up, -back), V(thickness, height, math.abs(ac:Dot(back))), color, material, opts)
end

local function pickShard()
	return SHARDS[1 + math.floor(rand() * #SHARDS)]
end

--- Bir yüzeye kırık zırh kıymıkları dizer: rastgele yönlü, hafifçe kalkık üçgen levhalar.
local function armor(group, surfaceParts, sampler, count, opts)
	for _ = 1, count do
		local s = lerp(opts.from, opts.to, rand())
		local c = sampler.at(s)
		local d = sampler.dir(s)
		local up = V(0, 1, 0)
		local dorsal = (up - d * up:Dot(d)).Unit
		local side = d:Cross(dorsal).Unit
		local a = jitter(opts.spread)
		local ray = (dorsal * math.cos(a) + side * math.sin(a)).Unit
		local pos = c.pos + ray * (surfaceDistance(surfaceParts, c.pos, ray) - 0.05)
		local size = opts.size * (0.7 + 0.6 * rand())
		local angle = rand() * math.pi * 2
		local tangent = (d * math.cos(angle) + ray:Cross(d).Unit * math.sin(angle)).Unit
		local normal = (ray + V(jitter(0.25), jitter(0.25), jitter(0.25))).Unit
		triangle("Kiymik", group, c.bone, pos - tangent * size * 0.4, pos + tangent * size * 0.7, size * (0.8 + 0.5 * rand()), normal, 0.26,
			pickShard(), if rand() < 0.6 then M.SmoothPlastic else M.Slate, { reflectance = 0.06, register = opts.register })
	end
end

--- Deriye serpilmiş küçük parlak kor zerreleri.
local function specks(group, surfaceParts, sampler, count, opts)
	for _ = 1, count do
		local s = lerp(opts.from or 0, opts.to or sampler.total, rand())
		local c = sampler.at(s)
		local d = sampler.dir(s)
		local up = V(0, 1, 0)
		local dorsal = (up - d * up:Dot(d)).Unit
		local side = d:Cross(dorsal).Unit
		local a = jitter(opts.spread or 2.6)
		local ray = (dorsal * math.cos(a) + side * math.sin(a)).Unit
		local pos = c.pos + ray * (surfaceDistance(surfaceParts, c.pos, ray) - 0.03)
		local r = 0.12 + 0.12 * rand()
		ellipsoid("Kor", group, c.bone, CFrame.new(pos), V(r, r, r), C.gold, M.Neon, { glow = true, shadow = false, query = false, register = opts.register })
	end
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("govde", nil, V(0, 7.9, 0.8))
addBone("omuz", "govde", V(0, 8.3, -2.2))
addBone("boyun", "omuz", V(0, 8.0, -4.4))
addBone("bas", "boyun", V(0, 7.2, -6.2))
addBone("arka", "govde", V(0, 7.8, 3.6))
addBone("kuyruk1", "arka", V(0, 8.0, 7.5))
addBone("kuyruk2", "kuyruk1", V(0, 6.9, 8.1))
local headFrame = CFrame.new(pivotOf("bas")) * CFrame.Angles(rad(-24), 0, 0)
local function H(x, y, z)
	return headFrame * V(x, y, z)
end
local function HD(x, y, z)
	return headFrame:VectorToWorldSpace(V(x, y, z))
end
local function HCF(x, y, z)
	return headFrame * CFrame.new(x, y, z)
end
addBone("cene", "bas", H(0, -0.9, -1.0))
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	addBone("kulak" .. side, "bas", H(s * 1.15, 1.5, 0.6))
end

-- ═════════════════════════════ GÖVDE ═════════════════════════════
local bodyParts, body = smoothTube("Govde", "Govde", {
	ctl(V(0, 7.3, 7.1), 4.0, 4.4, "arka"),
	ctl(V(0, 7.6, 5.6), 5.6, 6.0, "arka"),
	ctl(V(0, 7.8, 3.6), 6.4, 6.6, "arka"),
	ctl(V(0, 7.9, 0.8), 6.8, 7.0, "govde"),
	ctl(V(0, 8.3, -2.2), 6.4, 7.2, "omuz"),
	ctl(V(0, 8.0, -4.4), 5.0, 5.6, "boyun"),
	ctl(V(0, 7.2, -6.2), 3.8, 4.2, "bas"),
}, 0.8, 4.4, C.skin, M.Slate)
table.insert(bodyParts, ellipsoid("Karin", "Govde", "govde", CFrame.new(0, 6.3, 1.0), V(5.6, 3.4, 8.0), C.skin, M.Slate))
table.insert(bodyParts, ellipsoid("Kambur", "Govde", "omuz", CFrame.new(0, 9.7, -2.0), V(5.0, 3.0, 4.4), C.skin, M.Slate))
for _, s in { 1, -1 } do
	ellipsoid("OmuzDerisi", "Govde", "omuz", CFrame.new(s * 2.5, 6.9, -2.4), V(2.6, 3.8, 3.4), C.skin, M.Slate)
	ellipsoid("KalcaDerisi", "Govde", "arka", CFrame.new(s * 2.6, 7.0, 4.4), V(2.8, 4.2, 3.8), C.skin, M.Slate)
end
-- boynun deri kıvrımları
for _, s in { 10.5, 11.2, 11.9 } do
	local c = body.at(s)
	ellipsoid("Kivrim", "Govde", c.bone, lookFrame(c.pos, body.dir(s)), V(c.w + 0.35, c.h + 0.35, 0.5), C.fold, M.Slate)
end
-- karnın altından sızan ateş
ellipsoid("KarinAtesi", "Govde", "govde", CFrame.new(0, 5.15, 1.0), V(3.6, 1.2, 6.4), C.glow, M.Neon, { glow = true, shadow = false, query = false })
-- sırtta ve böğürlerde kırık zırh kıymıkları, deride kor zerreleri
armor("Govde", bodyParts, body, 62, { from = 0.8, to = 9.4, spread = 1.9, size = 2.0 })
armor("Govde", bodyParts, body, 10, { from = 9.4, to = 11.6, spread = 1.4, size = 1.3 })
specks("Govde", bodyParts, body, 40, { from = 0.5, to = body.total - 1.5, spread = 2.6 })
-- ensede kısa, sert yele dikenleri
do
	local s = 12.2
	while s > 8.6 do
		local c = body.at(s)
		local d = body.dir(s)
		local up = V(0, 1, 0)
		local dorsal = (up - d * up:Dot(d)).Unit
		local base = c.pos + dorsal * (surfaceDistance(bodyParts, c.pos, dorsal) - 0.15)
		local h = 0.5 + 0.45 * rand()
		spike("Yele", "Govde", c.bone, base + V(jitter(0.2), 0, 0), dorsal + V(jitter(0.2), 0, 0), d, h, h * 0.6, 0.18, C.ridge, M.SmoothPlastic)
		s -= 0.38
	end
end

-- ═════════════════════════════ BAŞ ═════════════════════════════
local function hctl(x, y, z, w, h, bone)
	return ctl(H(x, y, z), w, h, bone or "bas")
end
local headParts, head = smoothTube("Kafa", "Bas", {
	hctl(0, 0.3, 0.6, 3.4, 3.6),
	hctl(0, 0.15, -1.4, 3.1, 3.1),
	hctl(0, -0.05, -3.2, 2.6, 2.5),
	hctl(0, -0.25, -4.7, 2.4, 2.1),
	hctl(0, -0.45, -5.6, 2.0, 1.7),
}, 0.5, 3.0, C.skin, M.Slate)
smoothTube("Cene", "Bas", {
	hctl(0, -1.1, -1.6, 2.4, 1.3, "cene"),
	hctl(0, -1.2, -3.4, 2.1, 1.1, "cene"),
	hctl(0, -1.15, -4.9, 1.8, 0.95, "cene"),
}, 0.6, 2.2, C.skin, M.Slate)
-- ateşli ağız: dudakların arasından sızan parıltı
ellipsoid("Agiz", "Bas", "bas", HCF(0, -0.9, -4.0), V(1.6, 0.4, 2.3), C.glow, M.Neon, { glow = true, shadow = false })
ellipsoid("AgizAlt", "Bas", "cene", HCF(0, -0.95, -3.9), V(1.5, 0.35, 2.2), C.glow, M.Neon, { glow = true, shadow = false })
ellipsoid("DudakAtesi", "Bas", "bas", HCF(0, -0.78, -5.5), V(1.3, 0.4, 0.45), C.glow, M.Neon, { glow = true, shadow = false })
local nostrils = {}
for _, s in { 1, -1 } do
	-- burun delikleri, küçük koyu göz, kaş kıvrımı
	local o = H(0, -0.2, -5.0)
	local d = HD(s * 0.75, 0.25, -0.6).Unit
	table.insert(nostrils, ellipsoid("BurunDeligi", "Bas", "bas", lookFrame(o + d * (surfaceDistance(headParts, o, d) - 0.05), HD(0, 0, -1), d), V(0.5, 0.2, 0.35),
		C.nostril, M.SmoothPlastic, { shadow = false }))
	local eo = H(0, 0.55, -2.4)
	local ed = HD(s, 0.15, -0.1).Unit
	local eyePos = eo + ed * (surfaceDistance(headParts, eo, ed) - 0.06)
	ellipsoid("Goz", "Bas", "bas", lookFrame(eyePos, HD(0, 0, -1), ed), V(0.3, 0.18, 0.42), C.eye, M.SmoothPlastic, { shadow = false })
	ellipsoid("GozIsiltisi", "Bas", "bas", CFrame.new(eyePos + ed * 0.08 + HD(0, 0.05, -0.08)), V(0.09, 0.09, 0.09), C.gold, M.Neon, { shadow = false, query = false })
	ellipsoid("GozKivrimi", "Bas", "bas", lookFrame(eyePos + HD(0, 0.28, 0.1), HD(0, 0, -1), ed), V(0.55, 0.24, 0.8), C.fold, M.Slate)
	-- yanakta deri kıvrımları
	for k = 0, 2 do
		local co = H(0, -0.3 - k * 0.2, -1.8 - k * 0.5)
		local cd = HD(s, -0.1, 0).Unit
		ellipsoid("YanakKivrimi", "Bas", "bas", lookFrame(co + cd * (surfaceDistance(headParts, co, cd) - 0.08), HD(0, 1, 0.3), cd), V(0.25, 0.2, 1.4), C.fold, M.Slate)
	end
end
-- boynuzlar: koyu tabandan altın uca doğru incelen pürüzsüz eğriler, uçları parlar
local hornTips = {}
local function horn(points, baseWidth)
	-- Catmull-Rom ile sık noktalar
	local dense = {}
	local n = #points
	for i = 1, n - 1 do
		local p0, p1, p2, p3 = points[math.max(1, i - 1)], points[i], points[i + 1], points[math.min(n, i + 2)]
		for k = 0, 3 do
			local t = k / 4
			local t2, t3 = t * t, t * t * t
			table.insert(dense, (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
		end
	end
	table.insert(dense, points[n])
	local count = #dense
	for i = 1, count - 1 do
		local u = (i - 1) / (count - 2)
		local w = lerp(baseWidth, baseWidth * 0.22, u)
		local color = if u < 0.5 then C.hornBase:Lerp(C.hornMid, u * 2) else C.hornMid:Lerp(C.gold, (u - 0.5) * 2)
		local hot = u > 0.8
		segment("Boynuz", "Bas", "bas", dense[i], dense[i + 1], w, w, color, if hot then M.Neon else M.SmoothPlastic,
			{ extend = 2.2, glow = hot, reflectance = if hot then nil else 0.1 })
	end
	local tip = spike("BoynuzUcu", "Bas", "bas", dense[count] - (dense[count] - dense[count - 1]).Unit * 0.1, dense[count] - dense[count - 1], HD(0, 0, 1),
		baseWidth * 0.45, baseWidth * 0.2, baseWidth * 0.18, C.gold, M.Neon, { glow = true, shadow = false })
	table.insert(hornTips, tip)
end
horn({ H(0, 0.75, -4.6), H(0, 1.8, -5.1), H(0, 2.85, -5.35), H(0, 3.7, -5.3), H(0, 4.3, -4.95) }, 1.5)
horn({ H(0, 1.25, -2.9), H(0, 1.95, -3.15), H(0, 2.55, -3.2), H(0, 2.95, -3.0) }, 1.0)
-- kulaklar: dışa dönük, içi koyu
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local bone = "kulak" .. side
	local base = pivotOf(bone)
	local dir = HD(s * 0.5, 1, 0.35).Unit
	segment("Kulak", "Bas", bone, base, base + dir * 1.3, 0.75, 0.55, C.skin, M.Slate, { extend = 1.25, up = HD(s, 0, 0) })
	segment("IcKulak", "Bas", bone, base + dir * 0.2 + HD(0, 0, -0.18), base + dir * 1.15 + HD(0, 0, -0.18), 0.45, 0.2, C.skinDark, M.SmoothPlastic,
		{ extend = 1.1, up = HD(0, 0, -1) })
end
armor("Bas", headParts, head, 8, { from = 0.5, to = 3.0, spread = 1.3, size = 0.9 })
specks("Bas", headParts, head, 10, { from = 0.5, to = head.total - 0.5, spread = 2.4 })

-- ═════════════════════════════ KUYRUK ═════════════════════════════
segment("Kuyruk", "Govde", "kuyruk1", pivotOf("kuyruk1"), pivotOf("kuyruk2"), 0.6, 0.6, C.skin, M.Slate, { extend = 1.2 })
segment("Kuyruk", "Govde", "kuyruk2", pivotOf("kuyruk2"), V(0, 5.5, 8.4), 0.4, 0.4, C.skin, M.Slate, { extend = 1.15 })
ellipsoid("KuyrukPuskulu", "Govde", "kuyruk2", CFrame.new(0, 5.2, 8.45), V(0.45, 0.9, 0.45), C.skinDark, M.Slate)

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
-- Bacak bölümlerinin dinlenme çerçeveleri, oyundaki ters kinematikle aynı işlevlerle hesaplanır.
local rigSource = fs.readFile("src/rig.luau")
local RigCode = luau.load(rigSource, {
	debugName = "rig",
	environment = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, legs = {}, glowGroups = {}, floaters = {} } },
})()

local legs = {}
for _, def in {
	{ side = 1, front = true }, { side = -1, front = true }, { side = 1, front = false }, { side = -1, front = false },
} do
	local s = def.side
	local hip, knee, ankle, ball, bone, pole
	if def.front then
		hip, knee, ankle, ball = V(s * 2.3, 6.4, -2.6), V(s * 2.5, 4.0, -1.4), V(s * 2.4, 1.5, -2.5), V(s * 2.4, 0.7, -2.8)
		bone, pole = "omuz", V(s * 0.1, 0, 1)
	else
		hip, knee, ankle, ball = V(s * 2.3, 6.8, 4.4), V(s * 2.5, 4.3, 3.2), V(s * 2.4, 2.0, 4.6), V(s * 2.4, 0.7, 4.1)
		bone, pole = "arka", V(s * 0.1, 0, -1)
	end
	local l1, l2 = (knee - hip).Magnitude, (ankle - knee).Magnitude
	local upperCF, lowerCF = RigCode.legFrames(hip, ankle, pole, l1, l2)
	local frames = { upper = upperCF, lower = lowerCF, meta = RigCode.frame(ankle, ball - ankle, V(0, 0, -1)), foot = CFrame.new(ball) }
	local lm = (ball - ankle).Magnitude
	local group = "Bacak" .. (if def.front then "On" else "Arka") .. (if s > 0 then "L" else "R")
	local leg = { side = s, front = def.front, scraper = def.front and s < 0, bone = bone, hip = hip - pivotOf(bone), ball = ball, meta = ankle - ball,
		l1 = l1, l2 = l2, pole = pole, groups = { upper = {}, lower = {}, meta = {}, foot = {} } }
	local function registerFor(key)
		return function(part)
			table.insert(leg.groups[key], { name = part.Name, offset = frames[key]:Inverse() * part.CFrame })
		end
	end
	local function piece(key, prefix, localCF, size, color, material, opts)
		opts = opts or {}
		opts.register = registerFor(key)
		return ellipsoid(prefix, group, nil, frames[key] * localCF, size, color, material or M.Slate, opts)
	end
	piece("upper", "Ust", CFrame.new(0, 0, -l1 * 0.45), V(2.5, 2.6, l1 * 1.5), C.skin)
	piece("lower", "Alt", CFrame.new(0, 0, -l2 * 0.5), V(2.1, 2.15, l2 * 1.45), C.skin)
	piece("lower", "DizKivrimi", CFrame.new(0, 0.05, -0.25), V(2.15, 2.2, 0.8), C.fold)
	piece("meta", "Bilek", CFrame.new(0, 0, -lm * 0.45), V(1.95, 1.95, lm * 1.9), C.skin)
	piece("foot", "Taban", CFrame.new(0, 0.05, -0.15), V(2.25, 1.5, 2.3), C.skin)
	for i, dx in { -0.65, 0, 0.65 } do
		local nailBase = ball + V(dx, -0.4, -1.05 + math.abs(dx) * 0.25)
		spike("Tirnak", group, nil, nailBase, V(0, 0.25, -1), V(0, 1, 0), 0.55, 0.45, 0.55, C.nail, M.SmoothPlastic, { register = registerFor("foot") })
	end
	-- üst bacakta birkaç zırh kıymığı
	for _ = 1, 3 do
		local a = jitter(1.6) + (if s > 0 then 1.57 else -1.57)
		local localPos = CFrame.new(math.cos(a) * 1.2, math.sin(a) * 1.2, -l1 * (0.25 + 0.4 * rand()))
		local p = upperCF * localPos
		local normal = upperCF:VectorToWorldSpace(V(math.cos(a), math.sin(a), 0))
		local tangent = upperCF:VectorToWorldSpace(V(0, 0, -1))
		triangle("Kiymik", group, nil, p.Position - tangent * 0.5, p.Position + tangent * 0.9, 1.1, normal, 0.24, pickShard(), M.SmoothPlastic,
			{ register = registerFor("upper"), reflectance = 0.06 })
	end
	table.insert(legs, leg)
end

-- ═════════════════════════════ SAVRULAN KIYMIKLAR ═════════════════════════════
-- Sırttan kopup havaya savrulan kıymıklar: animasyon script'i her karede konumlarını hesaplar.
local floaters = {}
for k = 1, 12 do
	local s = lerp(1.5, 9.0, rand())
	local c = body.at(s)
	local base = c.pos + V(jitter(1.8), 3.2 + jitter(0.4), 0)
	local glowing = k % 4 == 0
	local size = 0.5 + 0.5 * rand()
	local p = basePart("WedgePart", "Ucan", "UcanKiymiklar", nil, CFrame.new(base), V(0.12, size, size * (0.8 + 0.4 * rand())),
		if glowing then C.gold else pickShard(), if glowing then M.Neon else M.SmoothPlastic, { shadow = false, query = false, transparency = 1 })
	table.insert(floaters, {
		name = p.Name,
		bone = c.bone,
		base = base - pivotOf(c.bone),
		drift = V(jitter(1.5), 2.5 + 1.5 * rand(), 3 + 3 * rand()),
		period = 3 + 2 * rand(),
		phase = rand(),
		spin = V(jitter(3), jitter(3), jitter(3)),
	})
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
local EMBER = seq({ { 0, RGB(255, 230, 140) }, { 0.5, RGB(255, 160, 50) }, { 1, RGB(255, 80, 10) } })
local DUST = seq({ { 0, RGB(120, 108, 96) }, { 1, RGB(70, 64, 60) } })

-- sırttan geriye savrulan kıvılcımlar ve ince duman
for _, part in { bodyParts[3], bodyParts[7], bodyParts[11] } do
	emitter(part, "Kivilcim", {
		Texture = SPARKLE, Color = EMBER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.4 }, { 1, 0 } }),
		Lifetime = NumberRange.new(2, 3.5), Rate = 9, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(50, 50),
		Acceleration = V(0, 2.5, 3.5), Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top,
	})
end
emitter(bodyParts[2], "Duman", {
	Texture = SMOKE, Color = seq({ { 0, RGB(70, 60, 54) }, { 1, RGB(30, 28, 28) } }), LightInfluence = 0.6,
	Size = nums({ { 0, 1.5 }, { 1, 5 } }), Transparency = nums({ { 0, 0.6 }, { 1, 1 } }), Lifetime = NumberRange.new(3, 4),
	Rate = 2.5, Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(30, 30), Acceleration = V(0, 1.5, 2.5),
	Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20), EmissionDirection = Enum.NormalId.Top,
})
-- boynuz uçlarında pırıltı; boynuz savrulunca kıvılcım patlaması
for _, tip in hornTips do
	emitter(tip, "BoynuzPiriltisi", {
		Texture = SPARKLE, Color = EMBER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.3 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.8, 1.4), Rate = 3, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
	})
	emitter(tip, "BoynuzKivilcimi", {
		Texture = SPARKLE, Color = EMBER, LightEmission = 1, LightInfluence = 0, Size = nums({ { 0, 0.55 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.6, 1.2), Rate = 0, Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(60, 60),
		Acceleration = V(0, -20, 0), Drag = 1, Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top,
		attributes = { SavurmaEfekti = true, Adet = 35 },
	})
end
local hornLight = Instance.new("PointLight")
hornLight.Name = "BoynuzIsigi"
hornLight.Color = RGB(255, 180, 70)
hornLight.Range = 12
hornLight.Brightness = 1.2
hornLight.Shadows = false
hornLight.Parent = hornTips[1]
-- burundan soluk
for _, n in nostrils do
	emitter(n, "Soluk", {
		Texture = SMOKE, Color = seq({ { 0, RGB(150, 140, 130) }, { 1, RGB(90, 86, 84) } }), LightInfluence = 0.6,
		Size = nums({ { 0, 0.5 }, { 1, 2.6 } }), Transparency = nums({ { 0, 0.4 }, { 1, 1 } }), Lifetime = NumberRange.new(0.8, 1.3),
		Rate = 0, Speed = NumberRange.new(4, 7), SpreadAngle = Vector2.new(15, 15), Drag = 2, Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Front, attributes = { Soluk = true, Adet = 8 },
	})
end
-- yer eşelerken sağ ön ayağın altından kalkan toz
for _, leg in legs do
	if leg.scraper then
		local pad = folder("BacakOnR"):FindFirstChild(leg.groups.foot[1].name)
		emitter(pad, "EseleTozu", {
			Texture = SMOKE, Color = DUST, LightInfluence = 0.8, Size = nums({ { 0, 0.8 }, { 1, 3 } }), Transparency = nums({ { 0, 0.45 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.8, 1.3), Rate = 40, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(50, 20), Drag = 2,
			Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Back, Enabled = false, attributes = { EseleTozu = true },
		})
	end
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
-- hücumda ön ayakların altından kalkan toz bulutu
local dustOut = attachment(root, "HucumTozu", CFrame.new(0, 0.3, -3.0))
emitter(dustOut, "Toz", {
	Texture = SMOKE, Color = DUST, LightInfluence = 0.8, Size = nums({ { 0, 1.5 }, { 1, 6 } }), Transparency = nums({ { 0, 0.4 }, { 1, 1 } }),
	Lifetime = NumberRange.new(1.2, 2.0), Rate = 0, Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(80, 15), Drag = 2.5,
	Acceleration = V(0, 1.5, 0), Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top,
	attributes = { HucumTozu = true, Adet = 45 },
})

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
collider("GovdeCarpisma", CFrame.new(0, 7.6, 0.8), V(6.6, 6.4, 13))
collider("BacakCarpisma", CFrame.new(0, 2.4, 0.8), V(6.2, 4.8, 9.6))
collider("BasCarpisma", CFrame.new(0, 6.0, -9.2), V(3.4, 4.2, 6.2))

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
-- Bacaklar: kök kemiğe göre, ayak ve bilek model uzayında; parçalar bacak bölümlerine göre.
table.insert(lines, "Rig.legs = {")
for _, leg in legs do
	table.insert(lines, string.format("\t{ side = %d, front = %s, scraper = %s, bone = %d, hip = %s, ball = %s, meta = %s, l1 = %s, l2 = %s, pole = %s, groups = {",
		leg.side, tostring(leg.front), tostring(leg.scraper), boneIndex[leg.bone], v3(leg.hip), v3(leg.ball), v3(leg.meta), fmt(leg.l1), fmt(leg.l2), v3(leg.pole)))
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
-- Parlayan parçalar nabız gecikmesine göre gruplanır (0.2 sn'lik dilimler).
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
table.insert(lines, "Rig.floaters = {")
for _, f in floaters do
	table.insert(lines, string.format("\t{ name = %q, bone = %d, base = %s, drift = %s, period = %s, phase = %s, spin = %s },",
		f.name, boneIndex[f.bone], v3(f.base), v3(f.drift), fmt(f.period), fmt(f.phase), v3(f.spin)))
end
table.insert(lines, "}")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "GergedanRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("ZirhliGergedan.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("ZirhliGergedan.rbxmx yazıldı: %d parça (%d parlayan), %d kemik, %d savrulan kıymık", count, #glowParts, #bones, #floaters))
for name, f in folders do
	print(string.format("  %-14s %d", name, #f:GetChildren()))
end
