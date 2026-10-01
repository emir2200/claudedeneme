-- ─────────────────────────────────────────────────────────────────────────────
-- Raptorun iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts, Rig.legs,
-- Rig.lids) ALTINA eklenir ve birlikte "RaptorRig" ModuleScript'ini oluşturur. Yalnızca
-- CFrame/Vector3/math kullanır; Roblox servislerine dokunmaz, bu sayede aynı kod Lune ile
-- bilgisayarda da test edilir.
--
-- Gövde, boyun, baş, kollar ve kuyruk kemiklere bağlıdır. Bacaklar ters kinematikle (IK)
-- çözülür: ayak yere basılı kalır, bilek ayağa göre konumlanır, diz iki parçanın uzunluğuna
-- göre her karede yeniden hesaplanır. Böylece raptor çömelip öne atılırken ayakları kaymaz.
-- Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles
local UP = Vector3.new(0, 1, 0)

Rig.ROAR_DURATION = 3.8
Rig.ROAR_INTERVAL = 12
Rig.BREATH_PERIOD = 2.6
Rig.LOOK_PERIOD = 2.4
Rig.TAP_PERIOD = 10
Rig.SHIFT_PERIOD = 13
Rig.BLINK_PERIOD = 4.7

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

--- Tamsayıdan 0..1 arası tekrarlanabilir sözde rastgele sayı.
local function hash(n: number): number
	local x = math.sin(n * 127.1 + 311.7) * 43758.5453
	return x - math.floor(x)
end

--- Saldırı başlangıcından bu yana geçen süre `rt` için (hazırlık, saldırı) şiddetleri, 0..1.
--- 0.0–0.8 sn hazırlık (çömelir, başını indirir, kuyruğunu kaldırır), 0.8–3.0 sn öne atılma ve
--- çığlık, 3.0–3.8 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.8) * (1 - smooth((rt - 0.8) / 0.2))
	local roar = smooth((rt - 0.8) / 0.2) * (1 - smooth((rt - 3.0) / 0.8))
	return windup, roar
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
		local rt = (now + 3) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

--- Ağırlık aktarma: ara sıra bir ayak kısa süre yerden kalkıp yerine basar (0..1).
--- `side` +1 sol, -1 sağ.
function Rig.footLift(side: number, t: number, rt: number?): number
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local c = t % Rig.SHIFT_PERIOD
	local a = if side > 0 then 5.0 else 11.0
	return bump(c, a, a + 1.1, 0.35) * calm
end

--- Kalçanın dinlenme yerine göre ötelemesi ve dönüşü: nefes, ağırlık aktarma, çömelme, atılma.
function Rig.bodyOffset(t: number, rt: number?): (Vector3, number, number, number)
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local breath = math.sin(t * TAU / Rig.BREATH_PERIOD)
	local liftL, liftR = Rig.footLift(1, t, rt), Rig.footLift(-1, t, rt)
	local offset = Vector3.new(
		0.28 * (liftR - liftL) + 0.06 * math.sin(t * 0.37) * calm,
		0.06 * breath * calm - 1.0 * windup + 0.25 * roar,
		0.35 * windup - 1.4 * roar
	)
	local pitch = 0.02 * breath * calm - 0.12 * windup + 0.16 * roar
	local yaw = 0.05 * math.sin(t * 0.29) * calm
	local roll = 0.04 * (liftL - liftR)
	return offset, pitch, yaw, roll
end

local function lookTarget(n: number): (number, number, number)
	if hash(n + 3.1) < 0.25 then
		return 0, 0, 0 -- ara sıra dümdüz öne bakar
	end
	return (hash(n) * 2 - 1) * 0.5, (hash(n + 17.3) * 2 - 1) * 0.16, (hash(n + 41.7) * 2 - 1) * 0.32
end

--- Kuş gibi bakış: baş birkaç saniye bir noktaya sabitlenir, sonra hızla yeni bir yöne döner
--- ve merakla yana yatar. (sağa-sola, aşağı-yukarı, yana yatma) döner.
function Rig.headLook(t: number): (number, number, number)
	local n = math.floor(t / Rig.LOOK_PERIOD)
	local f = (t - n * Rig.LOOK_PERIOD) / 0.3
	local y0, p0, r0 = lookTarget(n - 1)
	local y1, p1, r1 = lookTarget(n)
	local b = smooth(f)
	return y0 + (y1 - y0) * b, p0 + (p1 - p0) * b, r0 + (r1 - r0) * b
end

--- Göz kırpma: birkaç saniyede bir, bazen iki kez üst üste.
function Rig.blink(t: number): boolean
	local n = math.floor(t / Rig.BLINK_PERIOD)
	local c = t - n * Rig.BLINK_PERIOD
	return c < 0.14 or (hash(n + 7.7) > 0.55 and c > 0.3 and c < 0.42)
end

--- Orak pençenin açısı: ara sıra bir ayağın orak pençesi yere tık tık vurur.
function Rig.sickleAngle(side: number, t: number, rt: number?): number
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local c = t % Rig.TAP_PERIOD
	local a = if side > 0 then 2.0 else 7.0
	local tap = bump(c, a, a + 1.6, 0.2) * math.abs(math.sin((c - a) * math.pi * 2.5)) * calm
	return -0.75 * tap + 0.2 * windup
end

--- Zaman `t` ve saldırı süresi `rt` için kemik dönüşleri (kemik sırası → CFrame).
function Rig.pose(t: number, rt: number?): { [number]: CFrame }
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local breath = math.sin(t * TAU / Rig.BREATH_PERIOD)
	local p = {}
	local function set(name: string, cf: CFrame)
		local i = Rig.boneIndex[name]
		if i then
			p[i] = cf
		end
	end

	local offset, pitch, yaw, roll = Rig.bodyOffset(t, rt)
	set("kalca", CFrame.new(offset) * A(pitch, yaw, roll))
	set("govde", A(0.02 * breath * calm - 0.04 * windup + 0.04 * roar, 0.03 * math.sin(t * 0.41) * calm, 0))
	set("gogus", A(0.02 * math.sin(t * TAU / Rig.BREATH_PERIOD + 0.5) * calm - 0.04 * windup + 0.05 * roar, 0, 0))

	-- Boyun ve baş: kuş gibi bakınır; hazırlıkta başı öne ve aşağı indirir, saldırıda başını
	-- kaldırıp ağzını sonuna kadar açarak çığlık atar.
	local lookYaw, lookPitch, lookRoll = Rig.headLook(t)
	local shake = roar * 0.06 * math.sin(t * 13)
	for name, share in { boyun1 = 0.2, boyun2 = 0.25, boyun3 = 0.25 } do
		set(name, A(calm * lookPitch * 0.3 - windup * 0.12 + roar * 0.1, calm * (lookYaw - yaw) * share + shake * 0.5, 0))
	end
	set("bas", A(calm * lookPitch * 0.4 - windup * 0.1 + roar * 0.28 + shake, calm * lookYaw * 0.3, calm * lookRoll + roar * 0.05 * math.sin(t * 9)))
	-- Çene: negatif X aşağı açar. Ara sıra hızlı tıkırtılar (raptor "konuşması").
	local chatter = bump(t % 9, 6.0, 7.2, 0.15) * calm
	set("cene", A(-(0.02 + 0.07 * chatter * math.abs(math.sin(t * 19)) + roar * (0.72 + 0.06 * math.sin(t * 21)) + windup * 0.05), 0, 0))

	-- Kuyruk: denge için sallanır; hazırlıkta ve saldırıda kalkıp kamçılanır.
	for i = 1, 6 do
		local wave = math.sin(t * 0.9 - i * 0.5)
		set("kuyruk" .. i, A(0.012 * math.sin(t * 0.7 - i * 0.4) - windup * 0.05 - roar * 0.04,
			(0.035 + 0.025 * i / 6) * wave * calm - yaw * 0.3 + roar * 0.07 * math.sin(t * 7 - i * 0.7), 0))
	end

	-- Kollar: pençeler kıvrılıp açılır; hazırlıkta geri çekilir, saldırıda öne ve yana açılır.
	for side, sgn in { L = 1, R = -1 } do
		local flex = math.sin(t * 1.1 + (if sgn > 0 then 0 else 1.8))
		set("kol" .. side, A(0.06 * flex * calm - 0.3 * windup + 0.7 * roar, sgn * 0.05 * flex * calm, sgn * (-0.1 * windup + 0.25 * roar)))
		set("onkol" .. side, A(-0.08 * flex * calm + 0.2 * windup - 0.3 * roar, 0, 0))
		set("el" .. side, A(0.12 * math.sin(t * 1.7 + sgn) * calm - 0.4 * roar, 0, 0))
	end
	return p
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
--- Üst (kalça → diz) ve alt (diz → bilek) parçaların çerçevelerini döner; -Z parça boyunca uzanır.
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

--- Bir bacağın bu andaki bölüm çerçeveleri (model uzayında): upper, lower, meta (bilek → ayak),
--- foot (ayak tabanı) ve sickle (orak pençe).
function Rig.solveLeg(leg, boneCFs: { CFrame }, t: number, rt: number?, scale: number)
	local offset = Rig.bodyOffset(t, rt)
	local lift = Rig.footLift(leg.side, t, rt)
	local ball = (leg.ball + Vector3.new(0, 0.75 * lift, -0.25 * lift)) * scale
	local foot = CFrame.new(ball) * A(-0.35 * lift, 0, 0)
	-- çömelince topuk geriye ve aşağı iner, şahlanınca parmak ucuna kalkar
	local heel = math.clamp(-offset.Y * 0.2, -0.15, 0.3)
	local ankle = ball + A(heel, 0, 0):VectorToWorldSpace(leg.meta * scale)
	local hip = boneCFs[leg.bone] * (leg.hip * scale)
	local upper, lower = Rig.legFrames(hip, ankle, Vector3.new(0, 0, -1) + Vector3.new(leg.side * 0.15, 0, 0), leg.l1 * scale, leg.l2 * scale)
	return {
		upper = upper,
		lower = lower,
		meta = Rig.frame(ankle, ball - ankle, Vector3.new(0, 0, -1)),
		foot = foot,
		sickle = foot * CFrame.new(leg.sickle * scale) * A(Rig.sickleAngle(leg.side, t, rt), 0, 0),
	}
end

return Rig
