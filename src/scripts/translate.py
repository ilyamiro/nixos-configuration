#!/usr/bin/env python3
"""
Serpantinum Ultra-Fast Translation Engine
Supports Google Chrome-Ex API, Lingva / MyMemory fallback, and local LRU caching.
"""

import sys
import os
import json
import re
import subprocess
import urllib.request
import urllib.parse
import hashlib
import time
import argparse

CACHE_DIR = os.path.expanduser("~/.cache/serpantinum")
CACHE_FILE = os.path.join(CACHE_DIR, "translation_cache.json")
MAX_CACHE_ENTRIES = 1000

SUPPORTED_LANGUAGES = [
    {"code": "auto", "name": "Auto Detect", "native": "Автоопределение"},
    {"code": "ru", "name": "Russian", "native": "Русский"},
    {"code": "en", "name": "English", "native": "English"},
    {"code": "de", "name": "German", "native": "Deutsch"},
    {"code": "es", "name": "Spanish", "native": "Español"},
    {"code": "fr", "name": "French", "native": "Français"},
    {"code": "it", "name": "Italian", "native": "Italiano"},
    {"code": "zh", "name": "Chinese", "native": "中文"},
    {"code": "ja", "name": "Japanese", "native": "日本語"},
    {"code": "ko", "name": "Korean", "native": "한국어"},
    {"code": "uk", "name": "Ukrainian", "native": "Українська"},
    {"code": "pl", "name": "Polish", "native": "Polski"},
    {"code": "tr", "name": "Turkish", "native": "Türkçe"},
    {"code": "pt", "name": "Portuguese", "native": "Português"},
    {"code": "nl", "name": "Dutch", "native": "Nederlands"},
    {"code": "ar", "name": "Arabic", "native": "العربية"},
    {"code": "hi", "name": "Hindi", "native": "हिन्दी"},
    {"code": "cs", "name": "Czech", "native": "Čeština"},
    {"code": "sv", "name": "Swedish", "native": "Svenska"},
    {"code": "el", "name": "Greek", "native": "Ελληνικά"},
    {"code": "he", "name": "Hebrew", "native": "עברית"},
    {"code": "id", "name": "Indonesian", "native": "Bahasa Indonesia"},
    {"code": "vi", "name": "Vietnamese", "native": "Tiếng Việt"},
    {"code": "fi", "name": "Finnish", "native": "Suomi"},
    {"code": "no", "name": "Norwegian", "native": "Norsk"},
    {"code": "da", "name": "Danish", "native": "Dansk"},
    {"code": "hu", "name": "Hungarian", "native": "Magyar"},
    {"code": "ro", "name": "Romanian", "native": "Română"},
    {"code": "bg", "name": "Bulgarian", "native": "Български"},
    {"code": "sr", "name": "Serbian", "native": "Српски"},
    {"code": "sk", "name": "Slovak", "native": "Slovenčina"},
    {"code": "be", "name": "Belarusian", "native": "Беларуская"},
    {"code": "kk", "name": "Kazakh", "native": "Қазақша"},
    {"code": "ka", "name": "Georgian", "native": "ქართული"},
    {"code": "hy", "name": "Armenian", "native": "Հայերեն"},
    {"code": "az", "name": "Azerbaijani", "native": "Azərbaycan"},
    {"code": "uz", "name": "Uzbek", "native": "Oʻzbekcha"}
]

def load_cache():
    if not os.path.exists(CACHE_FILE):
        return {}
    try:
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def save_cache(cache):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        if len(cache) > MAX_CACHE_ENTRIES:
            keys = list(cache.keys())[-MAX_CACHE_ENTRIES:]
            cache = {k: cache[k] for k in keys}
        tmp_file = f"{CACHE_FILE}.tmp.{os.getpid()}"
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False)
        os.replace(tmp_file, CACHE_FILE)
    except Exception:
        pass

def get_cache_key(text, src, dst):
    return hashlib.md5(f"{src}:{dst}:{text.strip()}".encode("utf-8")).hexdigest()

def translate_google_chrome(text, src="auto", dst="ru"):
    """
    Ultra-fast Google Chrome Extension API (~40-80ms response).
    """
    for client_id in ["dict-chrome-ex", "gtx"]:
        params = urllib.parse.urlencode({
            "client": client_id,
            "sl": src,
            "tl": dst,
            "dt": ["t", "bd", "rm"],
            "q": text
        }, doseq=True)
        
        url = f"https://translate.googleapis.com/translate_a/single?{params}"
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
                "Accept": "*/*",
                "Referer": "https://translate.google.com/"
            }
        )

        try:
            with urllib.request.urlopen(req, timeout=3.0) as response:
                raw = response.read().decode("utf-8")
                data = json.loads(raw)

            translated_chunks = []
            translit = ""
            if isinstance(data, list) and len(data) > 0 and isinstance(data[0], list):
                for chunk in data[0]:
                    if isinstance(chunk, list) and len(chunk) > 0 and chunk[0]:
                        translated_chunks.append(chunk[0])
                    if isinstance(chunk, list) and len(chunk) > 2 and chunk[2] and not translit:
                        translit = chunk[2]

            translated_text = "".join(translated_chunks)
            if not translated_text:
                continue

            detected_lang = src
            if len(data) > 2 and isinstance(data[2], str):
                detected_lang = data[2]

            synonyms = []
            if len(data) > 1 and isinstance(data[1], list) and data[1]:
                for pos_group in data[1]:
                    if isinstance(pos_group, list) and len(pos_group) >= 2:
                        pos_name = pos_group[0]
                        terms = pos_group[1] if isinstance(pos_group[1], list) else []
                        synonyms.append({
                            "part_of_speech": pos_name,
                            "meanings": terms[:5]
                        })

            return {
                "success": True,
                "translated_text": translated_text,
                "detected_lang": detected_lang,
                "transliteration": translit,
                "synonyms": synonyms,
                "engine": "google"
            }
        except Exception:
            continue

    raise RuntimeError("Google Chrome API unavailable")

def translate_google_web(text, src="auto", dst="ru"):
    """
    Google Translate Web API fallback.
    """
    params = urllib.parse.urlencode({
        "client": "gtx",
        "sl": src,
        "tl": dst,
        "dt": "t",
        "q": text
    })
    url = f"https://translate.googleapis.com/translate_a/single?{params}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0"}
    )
    with urllib.request.urlopen(req, timeout=3.0) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    
    chunks = []
    if isinstance(data, list) and len(data) > 0 and isinstance(data[0], list):
        for c in data[0]:
            if isinstance(c, list) and len(c) > 0 and c[0]:
                chunks.append(c[0])
    
    translated = "".join(chunks)
    if not translated:
        raise RuntimeError("Empty Google Web response")
    
    detected = data[2] if len(data) > 2 and isinstance(data[2], str) else src
    return {
        "success": True,
        "translated_text": translated,
        "detected_lang": detected,
        "transliteration": "",
        "synonyms": [],
        "engine": "google-web"
    }

def translate_mymemory(text, src="auto", dst="ru"):
    """
    MyMemory Translate fallback.
    """
    s = "en" if src == "auto" else src
    encoded = urllib.parse.quote(text[:500])
    url = f"https://api.mymemory.translated.net/get?q={encoded}&langpair={s}|{dst}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0"}
    )
    with urllib.request.urlopen(req, timeout=3.5) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    
    res_data = data.get("responseData", {})
    translated = res_data.get("translatedText", "")
    if not translated or "MYMEMORY WARNING" in translated:
        raise RuntimeError("MyMemory unavailable")
    
    return {
        "success": True,
        "translated_text": translated,
        "detected_lang": s,
        "transliteration": "",
        "synonyms": [],
        "engine": "mymemory"
    }

def execute_translation(text, src="auto", dst="ru", use_cache=True):
    start_time = time.time()
    clean_text = text.strip()
    if not clean_text:
        return {
            "success": True,
            "translated_text": "",
            "source_lang": src,
            "target_lang": dst,
            "detected_lang": src,
            "original_text": text,
            "transliteration": "",
            "synonyms": [],
            "cached": False,
            "elapsed_ms": 0
        }

    cache = load_cache() if use_cache else {}
    cache_key = get_cache_key(clean_text, src, dst)

    if use_cache and cache_key in cache:
        res = cache[cache_key]
        res["cached"] = True
        res["elapsed_ms"] = int((time.time() - start_time) * 1000)
        return res

    result = None
    engines = [translate_google_chrome, translate_google_web, translate_mymemory]
    last_error = ""

    for eng in engines:
        try:
            result = eng(clean_text, src, dst)
            if result and result.get("translated_text"):
                break
        except Exception as e:
            last_error = str(e)
            continue

    if not result or not result.get("translated_text"):
        return {
            "success": False,
            "error": last_error or "Translation failed across all engines",
            "source_lang": src,
            "target_lang": dst,
            "original_text": text,
            "translated_text": "",
            "elapsed_ms": int((time.time() - start_time) * 1000)
        }

    output = {
        "success": True,
        "source_lang": src,
        "target_lang": dst,
        "detected_lang": result.get("detected_lang", src),
        "original_text": text,
        "translated_text": result.get("translated_text", ""),
        "transliteration": result.get("transliteration", ""),
        "synonyms": result.get("synonyms", []),
        "engine": result.get("engine", "google"),
        "cached": False,
        "elapsed_ms": int((time.time() - start_time) * 1000)
    }

    if use_cache:
        cache[cache_key] = output
        save_cache(cache)

    return output

def speak_text(text, lang="ru"):
    clean_text = text.strip()
    if not clean_text:
        return
    import subprocess
    encoded = urllib.parse.quote(clean_text[:200])
    url = f"https://translate.google.com/translate_tts?ie=UTF-8&tl={lang}&client=tw-ob&q={encoded}"
    tts_dir = os.path.expanduser("~/.cache/serpantinum/tts")
    os.makedirs(tts_dir, exist_ok=True)
    tts_key = hashlib.md5(f"{lang}:{clean_text[:200]}".encode("utf-8")).hexdigest()
    tts_file = os.path.join(tts_dir, f"{tts_key}.mp3")
    if not os.path.exists(tts_file):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                with open(tts_file, "wb") as f:
                    f.write(resp.read())
        except Exception:
            pass
    target = tts_file if os.path.exists(tts_file) else url
    subprocess.run(["mpv", "--no-video", "--really-quiet", target], check=False)

def main():
    parser = argparse.ArgumentParser(description="Serpantinum Translator Engine")
    parser.add_argument("text", nargs="?", default="", help="Text to translate")
    parser.add_argument("--text", "-t", dest="opt_text", default="", help="Text to translate (flag option)")
    parser.add_argument("--from", "-f", dest="from_lang", default="auto", help="Source language (default: auto)")
    parser.add_argument("--to", dest="to_lang", default="ru", help="Target language (default: ru)")
    parser.add_argument("--json", action="store_true", help="Output detailed JSON response")
    parser.add_argument("--no-cache", action="store_true", help="Disable caching")
    parser.add_argument("--list-languages", action="store_true", help="List supported languages in JSON format")
    parser.add_argument("--tts", "--speak", action="store_true", help="Speak the text using Google Neural TTS")

    args = parser.parse_args()

    if args.list_languages:
        print(json.dumps(SUPPORTED_LANGUAGES, ensure_ascii=False, indent=2))
        return

    text = (args.opt_text or args.text or "").strip()
    if not text and not sys.stdin.isatty():
        text = sys.stdin.read().strip()

    if args.tts or getattr(args, "speak", False):
        target_lang = args.to_lang if args.to_lang != "auto" else "ru"
        speak_text(text, target_lang)
        return

    if not text:
        if args.json:
            print(json.dumps({"success": False, "error": "Empty text supplied"}), flush=True)
        else:
            print("", end="", flush=True)
        return

    res = execute_translation(text, src=args.from_lang, dst=args.to_lang, use_cache=not args.no_cache)

    if args.json:
        print(json.dumps(res, ensure_ascii=False), flush=True)
    else:
        if res.get("success"):
            print(res.get("translated_text", ""), flush=True)
        else:
            print(f"Error: {res.get('error', 'Translation failed')}", file=sys.stderr, flush=True)
            sys.exit(1)

if __name__ == "__main__":
    main()
