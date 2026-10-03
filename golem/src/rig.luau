-- ─────────────────────────────────────────────────────────────────────────────
-- Lav golemin iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts, Rig.legs,
-- Rig.glowGroups, Rig.eyes) ALTINA eklenir ve birlikte "GolemRig" ModuleScript'ini
-- oluşturur. Yalnızca CFrame/Vector3/math kullanır; Roblox servislerine dokunmaz, bu
-- sayede aynı kod Lune ile bilgisayarda da test edilir.
--
-- Gövde, baş ve kollar kemiklere bağlıdır. Bacaklar ters kinematikle (IK) çözülür: ayaklar
-- yere basılı kalır, golem çömelip yere vururken dizler kendiliğinden bükülür.
-- Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles
local UP = Vector3.new(0, 1, 0)

Rig.ROAR_DURATION = 3.8
Rig.ROAR_INTERVAL = 14
Rig.SLAM_TIME = 1.12 -- yumrukların yere değdiği an (saldırı başından itibaren saniye)
Rig.SHOCKWAVE_DURATION = 1.0
Rig.BREATH_PERIOD = 4.0
Rig.FLEX_PERIOD = 11
Rig.HEARTBEAT_PERIOD = 1.9

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

--- Saldırı başlangıcından bu yana geçen süre `rt` için (kaldırma, yere vurma) şiddetleri, 0..1.
--- 0.0–0.95 sn yumruklarını başının üstüne kaldırır, 0.95–1.12 sn hızla indirip yere vurur,
--- 2.4 sn'ye kadar çömelik kalır, 3.8 sn'de doğrulur.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local raise = smooth(rt / 0.85) * (1 - smooth((rt - 0.95) / 0.17))
	local slam = smooth((rt - 0.95) / 0.17) * (1 - smooth((rt - 2.4) / 1.4))
	return raise, slam
end

--- Şu an saldırı sürüyorsa başlangıcından geçen süreyi, sürmüyorsa nil döner.
--- `now` sunucu saatidir; bu sayede bütün oyuncular saldırıyı aynı anda görür.
function Rig.roarTime(now: number, auto: boolean, interval: number, manualStart: number?): number?
	if manualStart then
		local rt = now - manualStart
		if rt >= 0 and rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	if auto and interval > Rig.ROAR_DURATION then
		local rt = (now + 5) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

--- Yere vurmadan sonra yayılan şok dalgasının ilerlemesi (0..1), yoksa nil.
function Rig.shockwave(rt: number?): number?
	if rt == nil or rt < Rig.SLAM_TIME or rt > Rig.SLAM_TIME + Rig.SHOCKWAVE_DURATION then
		return nil
	end
	return (rt - Rig.SLAM_TIME) / Rig.SHOCKWAVE_DURATION
end

--- Ara sıra kaslarını gerer: yumruklarını sıkıp kollarını hafifçe kaldırır (0..1).
function Rig.flex(t: number, rt: number?): number
	local raise, slam = Rig.roarEnvelope(rt)
	return bump(t % Rig.FLEX_PERIOD, 6.0, 8.2, 0.6) * (1 - math.max(raise, slam))
end

--- Zaman `t` ve saldırı süresi `rt` için kemik dönüşleri (kemik sırası → CFrame).
function Rig.pose(t: number, rt: number?): { [number]: CFrame }
	local raise, slam = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(raise, slam)
	local breath = math.sin(t * TAU / Rig.BREATH_PERIOD)
	local flex = Rig.flex(t, rt)
	local sway = math.sin(t * 0.35)
	local p = {}
	local function set(name: string, cf: CFrame)
		local i = Rig.boneIndex[name]
		if i then
			p[i] = cf
		end
	end

	-- Kalça: ağır ağır salınır; kaldırırken geriye yaslanır, yere vururken çömelip öne eğilir.
	set("kok", CFrame.new(0.15 * sway * calm, 0.08 * breath * calm - 0.25 * raise - 1.6 * slam, 0.3 * raise - 0.9 * slam)
		* A(0.1 * raise - 0.35 * slam, 0.05 * math.sin(t * 0.27) * calm, 0.03 * sway * calm))
	set("govde", A(0.025 * breath * calm + 0.08 * raise - 0.12 * slam + 0.04 * flex, 0.06 * math.sin(t * 0.31 + 1) * calm, -0.02 * sway * calm))
	-- Baş: yavaşça etrafına bakar; kaldırırken başını kaldırıp kükrer, vururken yere bakar.
	set("bas", A((-0.05 + 0.04 * math.sin(t * 0.5)) * calm + 0.3 * raise - 0.15 * slam,
		(0.3 * math.sin(t * 0.23) + 0.1 * math.sin(t * 0.7)) * calm, 0.04 * math.sin(t * 0.4) * calm))

	-- Kollar: sarkar ve hafifçe sallanır; kaldırırken yumruklar başın üstüne çıkar, sonra öne
	-- ve aşağı, yere doğru savrulur.
	for side, sgn in { L = 1, R = -1 } do
		local swing = math.sin(t * 0.6 + (if sgn > 0 then 0 else 1.2))
		set("kol" .. side, A(0.06 * swing * calm + 0.35 * flex + 2.5 * raise + 0.6 * slam, sgn * 0.05 * swing * calm,
			sgn * (0.08 * calm + 0.25 * flex - 0.25 * raise + 0.05 * slam)))
		set("onkol" .. side, A(0.1 * calm + 0.05 * swing * calm + 0.5 * flex - 0.3 * raise - 0.05 * slam, 0, 0))
		set("yumruk" .. side, A(0.1 * math.sin(t * 1.3 + sgn) * calm + 0.3 * flex, 0, 0))
	end
	return p
end

--- Lav çatlaklarının parlaklığı, 0..1. `phase` parçanın göğüsten uzaklığına bağlı gecikmedir:
--- kalp atışı göğüsten kollara ve bacaklara doğru yayılır; kaldırırken parlaklık artar, yere
--- vurunca en parlak hâline çıkıp yavaşça söner.
function Rig.glow(t: number, rt: number?, phase: number): number
	local raise, slam = Rig.roarEnvelope(if rt then rt - phase * 0.4 else nil)
	local c = (t - phase) % Rig.HEARTBEAT_PERIOD
	local beat = math.exp(-(c / 0.12) ^ 2) + 0.6 * math.exp(-((c - 0.3) / 0.12) ^ 2)
	local flex = bump(t % Rig.FLEX_PERIOD, 6.0, 8.2, 0.6)
	return math.clamp(0.32 + 0.25 * beat + 0.25 * flex + 0.4 * raise + 0.55 * slam, 0, 1)
end

--- Pozdan, kemiklerin model uzayındaki CFrame'lerini hesaplar. `scale` Model:GetScale().
--- Poz öteleme de içerebilir (kalçanın inip kalkması); öteleme de ölçeklenir.
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

--- İki parçalı bacak için ters kinematik: kalça `hip`, bilek `ankle`, dizin bükülme yönü `pole`.
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

--- Bir bacağın bu andaki bölüm çerçeveleri (model uzayında): upper (uyluk), lower (baldır), foot (ayak).
function Rig.solveLeg(leg, boneCFs: { CFrame }, scale: number)
	local hip = boneCFs[leg.bone] * (leg.hip * scale)
	local upper, lower = Rig.legFrames(hip, leg.ankle * scale, leg.pole, leg.l1 * scale, leg.l2 * scale)
	return { upper = upper, lower = lower, foot = CFrame.new(leg.ball * scale) }
end

return Rig
