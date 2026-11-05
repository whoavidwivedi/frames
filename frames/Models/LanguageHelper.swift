import Foundation

public enum LanguageHelper: Sendable {
    private static let iso6392Map: [String: String] = [
        "aar": "Afar", "abk": "Abkhazian", "ace": "Achinese", "ach": "Acoli",
        "ada": "Adangme", "ady": "Adyghe", "afr": "Afrikaans", "aka": "Akan",
        "alb": "Albanian", "sqi": "Albanian", "amh": "Amharic", "ara": "Arabic",
        "arg": "Aragonese", "arm": "Armenian", "hye": "Armenian", "asm": "Assamese",
        "ava": "Avaric", "ave": "Avestan", "aym": "Aymara", "aze": "Azerbaijani",
        "bak": "Bashkir", "bam": "Bambara", "baq": "Basque", "eus": "Basque",
        "bel": "Belarusian", "ben": "Bengali", "bih": "Bihari", "bis": "Bislama",
        "bos": "Bosnian", "bre": "Breton", "bul": "Bulgarian", "bur": "Burmese",
        "mya": "Burmese", "cat": "Catalan", "cha": "Chamorro", "che": "Chechen",
        "chi": "Chinese", "zho": "Chinese", "chu": "Church Slavic", "chv": "Chuvash",
        "cor": "Cornish", "cos": "Corsican", "cre": "Cree", "cze": "Czech",
        "ces": "Czech", "dan": "Danish", "div": "Divehi", "dut": "Dutch",
        "nld": "Dutch", "dzo": "Dzongkha", "eng": "English", "epo": "Esperanto",
        "est": "Estonian", "ewe": "Ewe", "fao": "Faroese", "fij": "Fijian",
        "fin": "Finnish", "fre": "French", "fra": "French", "fry": "Western Frisian",
        "ful": "Fulah", "geo": "Georgian", "kat": "Georgian", "ger": "German",
        "deu": "German", "gla": "Gaelic", "gle": "Irish", "glg": "Galician",
        "glv": "Manx", "gre": "Greek", "ell": "Greek", "grn": "Guarani",
        "guj": "Gujarati", "hat": "Haitian", "hau": "Hausa", "heb": "Hebrew",
        "her": "Herero", "hin": "Hindi", "hmo": "Hiri Motu", "hrv": "Croatian",
        "scr": "Croatian", "hun": "Hungarian", "ibo": "Igbo", "ice": "Icelandic",
        "isl": "Icelandic", "ido": "Ido", "iii": "Sichuan Yi", "iku": "Inuktitut",
        "ile": "Interlingue", "ina": "Interlingua", "ind": "Indonesian", "ipk": "Inupiaq",
        "ita": "Italian", "jav": "Javanese", "jpn": "Japanese", "kal": "Kalaallisut",
        "kan": "Kannada", "kas": "Kashmiri", "kaz": "Kazakh", "khm": "Central Khmer",
        "kik": "Kikuyu", "kin": "Kinyarwanda", "kir": "Kirghiz", "kom": "Komi",
        "kon": "Kongo", "kor": "Korean", "kua": "Kuanyama", "kur": "Kurdish",
        "lao": "Lao", "lat": "Latin", "lav": "Latvian", "lim": "Limburgan",
        "lin": "Lingala", "lit": "Lithuanian", "ltz": "Luxembourgish", "lub": "Luba-Katanga",
        "lug": "Ganda", "mac": "Macedonian", "mkd": "Macedonian", "mah": "Marshallese",
        "mal": "Malayalam", "mao": "Maori", "mri": "Maori", "mar": "Marathi",
        "may": "Malay", "msa": "Malay", "mlg": "Malagasy", "mlt": "Maltese",
        "mon": "Mongolian", "nau": "Nauru", "nav": "Navajo", "nbl": "South Ndebele",
        "nde": "North Ndebele", "ndo": "Ndonga", "nep": "Nepali", "nno": "Norwegian Nynorsk",
        "nob": "Norwegian Bokmål", "nor": "Norwegian", "nya": "Chichewa", "oci": "Occitan",
        "oji": "Ojibwa", "ori": "Oriya", "orm": "Oromo", "oss": "Ossetian",
        "pan": "Panjabi", "per": "Persian", "fas": "Persian", "pli": "Pali",
        "pol": "Polish", "por": "Portuguese", "pus": "Pushto", "que": "Quechua",
        "roh": "Romansh", "rum": "Romanian", "ron": "Romanian", "run": "Rundi",
        "rus": "Russian", "sag": "Sango", "san": "Sanskrit", "sin": "Sinhala",
        "slo": "Slovak", "slk": "Slovak", "slv": "Slovenian", "sme": "Northern Sami",
        "smo": "Samoan", "sna": "Shona", "snd": "Sindhi", "som": "Somali",
        "sot": "Southern Sotho", "spa": "Spanish", "srd": "Sardinian", "srp": "Serbian",
        "scc": "Serbian", "ssw": "Swati", "sun": "Sundanese", "swa": "Swahili",
        "swe": "Swedish", "tah": "Tahitian", "tam": "Tamil", "tat": "Tatar",
        "tel": "Telugu", "tgk": "Tajik", "tgl": "Tagalog", "tha": "Thai",
        "tib": "Tibetan", "bod": "Tibetan", "tir": "Tigrinya", "ton": "Tonga",
        "tsn": "Tswana", "tso": "Tsonga", "tuk": "Turkmen", "tur": "Turkish",
        "twi": "Twi", "uig": "Uighur", "ukr": "Ukrainian", "urd": "Urdu",
        "uzb": "Uzbek", "ven": "Venda", "vie": "Vietnamese", "vol": "Volapük",
        "wel": "Welsh", "cym": "Welsh", "wln": "Walloon", "wol": "Wolof",
        "xho": "Xhosa", "yid": "Yiddish", "yor": "Yoruba", "zha": "Zhuang",
        "zul": "Zulu", "und": "Undetermined"
    ]

    private static let iso6391Map: [String: String] = [
        "en": "English", "es": "Spanish", "fr": "French", "de": "German",
        "ja": "Japanese", "zh": "Chinese", "hi": "Hindi", "ko": "Korean",
        "it": "Italian", "pt": "Portuguese", "ru": "Russian", "ar": "Arabic",
        "nl": "Dutch", "sv": "Swedish", "pl": "Polish", "tr": "Turkish",
        "da": "Danish", "fi": "Finnish", "no": "Norwegian", "el": "Greek",
        "he": "Hebrew", "id": "Indonesian", "th": "Thai", "vi": "Vietnamese",
        "cs": "Czech", "hu": "Hungarian", "ro": "Romanian", "uk": "Ukrainian",
        "ms": "Malay", "fa": "Persian", "bn": "Bengali", "ta": "Tamil",
        "te": "Telugu", "ur": "Urdu", "mr": "Marathi", "gu": "Gujarati",
        "kn": "Kannada", "ml": "Malayalam", "pa": "Panjabi"
    ]

    public static func displayName(for code: String?) -> String {
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Unknown"
        }
        let lower = raw.lowercased()
        if lower == "und" { return "Undetermined" }

        // Check our comprehensive ISO-639-2 map
        if let name = iso6392Map[lower] {
            return name
        }
        if let name = iso6391Map[lower] {
            return name
        }

        // BCP 47 prefix (e.g. en-US -> en)
        let primary = lower.components(separatedBy: "-")[0].components(separatedBy: "_")[0]
        if let name = iso6392Map[primary] {
            return name
        }
        if let name = iso6391Map[primary] {
            return name
        }

        // Apple Foundation Locale lookup
        if let name = Locale.current.localizedString(forIdentifier: lower) {
            return name.capitalized
        }
        if let name = Locale.current.localizedString(forLanguageCode: primary) {
            return name.capitalized
        }

        return raw.count <= 3 ? raw.uppercased() : raw.capitalized
    }

    public static func formattedTrackTitle(
        displayName: String?,
        language: String?,
        details: String? = nil
    ) -> String {
        let rawName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let langName = Self.displayName(for: language)
        let detailStr = details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var baseTitle: String
        if rawName.isEmpty || rawName.lowercased() == "undetermined" || rawName.lowercased() == "unknown" {
            baseTitle = langName
        } else if rawName.localizedCaseInsensitiveContains(langName) {
            baseTitle = rawName
        } else if langName != "Unknown" && langName != "Undetermined" {
            baseTitle = "\(rawName) (\(langName))"
        } else {
            baseTitle = rawName
        }

        if !detailStr.isEmpty && !baseTitle.localizedCaseInsensitiveContains(detailStr) {
            return "\(baseTitle) (\(detailStr))"
        }
        return baseTitle
    }

    public static func channelDescription(channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1 Surround"
        case 8: return "7.1 Surround"
        default:
            return channels > 0 ? "\(channels) ch" : "Stereo"
        }
    }

    public static func audioCodecDescription(codecID: String) -> String {
        let clean = codecID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch clean {
        case "A_AAC", "AAC", "MP4A": return "AAC"
        case "A_AC3", "AC3", "AC-3": return "Dolby Digital (AC-3)"
        case "A_EAC3", "EAC3", "EC-3": return "Dolby Digital Plus (E-AC-3)"
        case "A_DTS", "DTS": return "DTS"
        case "A_TRUEHD", "TRUEHD", "MLP": return "Dolby TrueHD"
        case "A_FLAC", "FLAC": return "FLAC Lossless"
        case "A_OPUS", "OPUS": return "Opus"
        case "A_VORBIS", "VORBIS": return "Vorbis"
        case "A_PCM/INT/LIT", "A_PCM/INT/BIG", "PCM", "LPCM", "IN24", "IN32": return "PCM Lossless"
        case "A_MP3", "MP3", ".MP3": return "MP3"
        case "A_ALAC", "ALAC": return "Apple Lossless (ALAC)"
        default:
            if clean.starts(with: "A_") {
                return String(clean.dropFirst(2))
            }
            return clean.isEmpty ? "Audio" : clean
        }
    }
}
