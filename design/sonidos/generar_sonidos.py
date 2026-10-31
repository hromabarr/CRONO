"""Genera los sonidos de alarma de Crono en Crono/Resources/Sounds.

Sin dependencias, como el icono: síntesis directa a WAV PCM de 16 bits.

    python design/sonidos/generar_sonidos.py

AlarmKit repite el sonido mientras la alarma suena, así que cada archivo es
un ciclo corto que encadena bien consigo mismo. Mono a 22 050 Hz: suena igual
por el altavoz de un iPhone y pesa la mitad.
"""

import math
import os
import struct
import wave

RATE = 22050
SECONDS = 12


def envelope(t, attack, release, length):
    """Sube en `attack` segundos y baja en los últimos `release`: sin chasquidos."""
    if t < attack:
        return t / attack
    if t > length - release:
        return max(0.0, (length - t) / release)
    return 1.0


def pulse():
    """Pitidos cortos a 880 Hz, cuatro por segundo en grupos: el clásico."""
    out = []
    for i in range(RATE * SECONDS):
        t = i / RATE
        cycle = t % 1.0
        beep = cycle % 0.25
        on = cycle < 0.75 and beep < 0.12
        value = math.sin(2 * math.pi * 880 * t) if on else 0.0
        out.append(value * envelope(beep, 0.005, 0.01, 0.12) * 0.8 if on else 0.0)
    return out


def bell():
    """Campana: parciales inarmónicos que decaen, una cada 1,5 s."""
    partials = [(523.0, 1.0), (1046.0, 0.5), (1371.0, 0.35), (1755.0, 0.2), (2637.0, 0.1)]
    out = []
    for i in range(RATE * SECONDS):
        t = i / RATE
        local = t % 1.5
        decay = math.exp(-local * 2.8)
        value = sum(a * math.sin(2 * math.pi * f * local) for f, a in partials)
        out.append(value * decay * min(1.0, local / 0.004) * 0.45)
    return out


def siren():
    """Sirena que sube y baja entre 650 y 1300 Hz. La más difícil de ignorar."""
    out = []
    phase = 0.0
    for i in range(RATE * SECONDS):
        t = i / RATE
        sweep = 0.5 - 0.5 * math.cos(2 * math.pi * t / 1.2)
        freq = 650 + 650 * sweep
        phase += 2 * math.pi * freq / RATE
        # Un poco de tercer armónico la hace más áspera, que es lo que se busca.
        value = math.sin(phase) + 0.3 * math.sin(3 * phase)
        out.append(value * 0.6)
    return out


def beep():
    """Tres pitidos agudos casi cuadrados y medio segundo de silencio."""
    out = []
    for i in range(RATE * SECONDS):
        t = i / RATE
        cycle = t % 1.0
        slot = cycle % 0.16
        on = cycle < 0.48 and slot < 0.09
        if on:
            square = 1.0 if math.sin(2 * math.pi * 2093 * t) >= 0 else -1.0
            out.append(square * envelope(slot, 0.003, 0.006, 0.09) * 0.35)
        else:
            out.append(0.0)
    return out


SOUNDS = {
    "pulso": pulse,
    "campana": bell,
    "sirena": siren,
    "pitido": beep,
}


def write(path, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.89 / peak if peak > 0.89 else 1.0
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(frames)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.abspath(os.path.join(here, "..", "..", "Crono", "Resources", "Sounds"))
    os.makedirs(target, exist_ok=True)
    for name, make in SOUNDS.items():
        path = os.path.join(target, name + ".wav")
        write(path, make())
        print(path, os.path.getsize(path))
