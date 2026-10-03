-- ─────────────────────────────────────────────────────────────────────────────
-- Zırhlı gergedanın iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts, Rig.legs,
-- Rig.glowGroups, Rig.floaters) ALTINA eklenir ve birlikte "GergedanRig" ModuleScript'ini
-- oluşturur. Yalnızca CFrame/Vector3/math kullanır; Roblox servislerine dokunmaz, bu sayede
-- aynı kod Lune ile bilgisayarda da test edilir.
--
-- Gövde, boyun, baş, kulaklar ve kuyruk kemiklere bağlıdır. Dört bacak ters kinematikle (IK)
-- çözülür: ayaklar yere basılı kalır, gövde öne atılırken dirsekler ve dizler kendiliğinden
-- bükülür. Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles
local UP = Vector3.new(0, 1, 0)

Rig.ROAR_DURATION = 4.2
Rig.ROAR_INTERVAL = 14
Rig.BREATH_PERIOD = 3.6
Rig.SNORT_PERIOD = 6.5
Rig.SCRAPE_PERIOD = 13
Rig.SCRAPE_LENGTH = 0.55

Rig.boneIndex = {}
for i, b in Rig.bones do
	Rig.boneIndex[b.name] = i
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--- a..b aralığında yumuşakça 0'dan 1'e çıkıp inen tümsek (kenarlarda `edge` sn geçiş).
local function bump(x: number, a: number, b: number, edge: number): number
	return smooth((x - a) / edge) * (1 - smooth((x - (b - edge)) / edge))
end

--- Hücum başlangıcından bu yana geçen süre `rt` için (hazırlık, hücum) şiddetleri, 0..1.
--- 0.0–1.4 sn hazırlık (başını indirir, ön ayağıyla iki kez yeri eşeler, burnundan soluk verir),
--- 1.4–3.4 sn öne atılma ve boynuz savurma, 3.4–4.2 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.4) * (1 - smooth((rt - 1.4) / 0.2))
	local charge = smooth((rt - 1.4) / 0.2) * (1 - smooth((rt - 3.4) / 0.8))
	return windup, charge
end

--- Şu an hücum sürüyorsa başlangıcından geçen süreyi, sürmüyorsa nil döner.
--- `now` sunucu saatidir; bu sayede bütün oyuncular hücumu aynı anda görür.
function Rig.roarTime(now: number, auto: boolean, interval: number, manualStart: number?): number?
	if manualStart then
		local rt = now - manualStart
		if rt >= 0 and rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	if auto and interval > Rig.ROAR_DURATION then
		local rt = (now + 4) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

--- Boynuz savurma (0..1): öne atıldıktan hemen sonra başını hızla yukarı kaldırıp indirir.
function Rig.toss(rt: number?): number
	if rt == nil then
		return 0
	end
	return bump(rt, 1.6, 2.4, 0.18)
end

--- Sağ ön ayakla yer eşeleme: ilerleme (0..1) ya da nil. Boştayken ara sıra bir kez, hücum
--- hazırlığında iki kez eşeler.
function Rig.scrape(t: number, rt: number?): number?
	if rt then
		for _, start in { 0.1, 0.75 } do
			if rt >= start and rt < start + Rig.SCRAPE_LENGTH then
				return (rt - start) / Rig.SCRAPE_LENGTH
			end
		end
		return nil
	end
	local c = t % Rig.SCRAPE_PERIOD
	if c >= 8 and c < 8 + Rig.SCRAPE_LENGTH then
		return (c - 8) / Rig.SCRAPE_LENGTH
	end
	return nil
end

--- Eşeleme ilerlemesinden ayağın kalkması, öne/arkaya kayması ve toz çıkıp çıkmadığı.
--- Ayak önce kalkıp öne uzanır, sonra yere basıp geriye doğru sürtülür (toz bu sırada çıkar).
function Rig.scrapeFoot(u: number?): (number, number, boolean)
	if u == nil then
		return 0, 0, false
	end
	if u < 0.5 then
		return 0.8 * math.sin(math.pi * u / 0.5), -1.2 * smooth(u / 0.5), false
	end
	return 0, -1.2 * (1 - smooth((u - 0.5) / 0.5)), true
end

--- Zaman `t` ve hücum süresi `rt` için kemik dönüşleri (kemik sırası → CFrame).
--- Kök kemiğin pozu öteleme de içerir: gövde nefesle inip kalkar, hücumda öne atılır.
function Rig.pose(t: number, rt: number?): { [number]: CFrame }
	local windup, charge = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, charge)
	local toss = Rig.toss(rt)
	local breath = math.sin(t * TAU / Rig.BREATH_PERIOD)
	local sway = math.sin(t * 0.3)
	local p = {}
	local function set(name: string, cf: CFrame)
		local i = Rig.boneIndex[name]
		if i then
			p[i] = cf
		end
	end

	set("govde", CFrame.new(0.1 * sway * calm, 0.08 * breath * calm - 0.35 * windup - 0.5 * charge, 0.3 * windup - 1.8 * charge)
		* A(0.02 * toss, 0.04 * math.sin(t * 0.25) * calm, 0.02 * sway * calm))
	set("omuz", A(0.02 * breath * calm - 0.05 * windup, 0, 0))
	set("arka", A(-0.012 * breath * calm, -0.03 * math.sin(t * 0.25) * calm, 0))

	-- Boyun ve baş: ağır ağır bakınır; hazırlıkta boynuzunu öne indirir, hücumda başını
	-- yukarı savurur ve böğürür.
	local look = (0.25 * math.sin(t * 0.21) + 0.08 * math.sin(t * 0.6)) * calm
	local nod = 0.04 * math.sin(t * 0.47) * calm
	local shake = charge * 0.05 * math.sin(t * 12)
	set("boyun", A(nod - 0.15 * windup - 0.15 * charge * (1 - toss) + 0.3 * toss, look * 0.5, 0))
	set("bas", A(nod * 0.8 - 0.28 * windup - 0.3 * charge * (1 - toss) + 0.85 * toss + shake, look * 0.5 + shake, 0.04 * math.sin(t * 0.37) * calm))
	set("cene", A(-(0.03 + 0.02 * (breath + 1) * calm + 0.28 * toss), 0, 0))
	-- Kulaklar: seğirir, hücumda geriye yatar.
	for side, sgn in { L = 1, R = -1 } do
		local flick = bump((t + (if sgn > 0 then 0 else 2.3)) % 5.1, 1.0, 1.4, 0.1) * calm
		set("kulak" .. side, A(0.5 * flick + 0.45 * charge + 0.2 * windup, sgn * 0.15 * math.sin(t * 0.5 + sgn) * calm, sgn * 0.25 * flick))
	end
	-- Kuyruk: sağa sola savrulur; hücumda kalkar.
	local swish = math.sin(t * 1.7) * (0.35 * calm + 0.15) + charge * 0.2 * math.sin(t * 9)
	set("kuyruk1", A(-0.4 * charge - 0.15 * windup, swish * 0.6, 0))
	set("kuyruk2", A(-0.2 * charge, swish, 0))
	return p
end

--- Lav ışıltısının (boynuz uçları, ağız, karın, zırh kıvılcımları) parlaklığı, 0..1.
--- `phase` parçanın göğüsten uzaklığına bağlı gecikmedir.
function Rig.glow(t: number, rt: number?, phase: number): number
	local windup, charge = Rig.roarEnvelope(rt)
	local pulse = 0.5 + 0.5 * math.sin((t - phase) * TAU / Rig.BREATH_PERIOD)
	local flicker = 0.08 * math.sin(t * 7.3 + phase * 13) * math.sin(t * 4.1 + phase * 7)
	return math.clamp(0.35 + 0.3 * pulse + flicker + 0.35 * windup + 0.6 * charge + 0.4 * Rig.toss(rt), 0, 1)
end

--- Pozdan, kemiklerin model uzayındaki CFrame'lerini hesaplar. `scale` Model:GetScale().
--- Poz öteleme de içerebilir (gövdenin inip kalkması); öteleme de ölçeklenir.
function Rig.solve(pose: { [number]: CFrame }, scale: number): { CFrame }
	local out = table.create(#Rig.bones)
	for i, b in Rig.bones do
		local cf = CFrame.new(b.rel * scale)
		local rot = pose[i]
		if rot then
			cf *= CFrame.new(rot.Position * scale) * rot.Rotation
		end
		out[i] = if b.parent > 0 then out[b.parent] * cf else cf
	end
	return out
end

--- -Z'si `look` yönüne bakan, Y'si `upHint`e yakın çerçeve.
function Rig.frame(pos: Vector3, look: Vector3, upHint: Vector3): CFrame
	look = look.Unit
	local right = look:Cross(upHint)
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.new(1, 0, 0))
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- İki parçalı bacak için ters kinematik: kök `hip`, bilek `ankle`, eklemin bükülme yönü `pole`.
function Rig.legFrames(hip: Vector3, ankle: Vector3, pole: Vector3, l1: number, l2: number): (CFrame, CFrame)
	local toAnkle = ankle - hip
	local d = math.clamp(toAnkle.Magnitude, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local u = toAnkle.Unit
	local v = pole - u * pole:Dot(u)
	v = if v.Magnitude > 1e-4 then v.Unit else UP
	local a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, l1 * l1 - a * a))
	local knee = hip + u * a + v * h
	return Rig.frame(hip, knee - hip, v), Rig.frame(knee, hip + u * d - knee, v)
end

--- Bir bacağın bu andaki bölüm çerçeveleri (model uzayında): upper, lower, meta (bilek → ayak), foot.
function Rig.solveLeg(leg, boneCFs: { CFrame }, t: number, rt: number?, scale: number)
	local lift, slide = 0, 0
	if leg.scraper then
		lift, slide = Rig.scrapeFoot(Rig.scrape(t, rt))
	end
	local ball = (leg.ball + Vector3.new(0, lift, slide)) * scale
	local foot = CFrame.new(ball) * A(-0.4 * lift, 0, 0)
	local ankle = ball + foot:VectorToWorldSpace(leg.meta * scale)
	local hip = boneCFs[leg.bone] * (leg.hip * scale)
	local upper, lower = Rig.legFrames(hip, ankle, leg.pole, leg.l1 * scale, leg.l2 * scale)
	return {
		upper = upper,
		lower = lower,
		meta = Rig.frame(ankle, ball - ankle, Vector3.new(0, 0, -1)),
		foot = foot,
	}
end

--- Sırttan kopup savrulan zırh kıymığının döngü içindeki konumu (kemiğe göre), dönüşü ve
--- görünmezliği (0 = görünür, 1 = görünmez).
function Rig.floater(f, t: number): (Vector3, CFrame, number)
	local u = (t / f.period + f.phase) % 1
	local pos = f.base + f.drift * u + Vector3.new(0.3 * math.sin(t * 2 + f.phase * 9), 0.2 * math.sin(t * 2.7 + f.phase * 5), 0)
	local rot = A(t * f.spin.X, t * f.spin.Y, t * f.spin.Z)
	local fade = 1 - smooth(u / 0.12) * (1 - smooth((u - 0.6) / 0.4))
	return pos, rot, fade
end

return Rig
