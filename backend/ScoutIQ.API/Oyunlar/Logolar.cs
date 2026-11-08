using System.Collections.Generic;

namespace ScoutIQ.API.Oyunlar
{
    // Kulüp dışındaki başlıkların görselleri: milli takım bayrakları, lig ve kupa logoları.
    // Kulüp logoları veritabanında (kulupler.logo_url); bunlar veritabanında olmadığı için burada tutulur.
    public static class Logolar
    {
        // Lig ve kupa logoları Transfermarkt'tan; uygulamada kulüp logoları gibi beyaz dairenin üstünde gösterilir
        private static string Transfermarkt(string kod) => $"https://tmssl.akamaized.net/images/logo/header/{kod}.png";

        // Lig kodu (TR1, GB1 ...) -> logo
        public static string? Lig(string kod) => Transfermarkt(kod.ToLowerInvariant());

        // Bingo'nun başarı anahtarı -> logo. Lig şampiyonlukları ligin logosunu kullanır. Ballon d'Or'un logosu yok.
        public static string? Basari(string anahtar) => anahtar switch
        {
            "sampiyonlar_ligi" => Transfermarkt("cl"),
            "avrupa_ligi" => Transfermarkt("el"),
            "dunya_kupasi" => Transfermarkt("fiwc"),
            "avrupa_sampiyonasi" => Transfermarkt("em24"),
            "copa_america" => Transfermarkt("copa"),
            "super_lig_sampiyonu" => Lig("TR1"),
            "premier_lig_sampiyonu" => Lig("GB1"),
            "la_liga_sampiyonu" => Lig("ES1"),
            "serie_a_sampiyonu" => Lig("IT1"),
            "bundesliga_sampiyonu" => Lig("L1"),
            "ligue_1_sampiyonu" => Lig("FR1"),
            _ => null
        };

        // Transfermarkt'taki İngilizce milli takım ismi -> bayrak. Artık olmayan ülkelerin (Sovyetler Birliği,
        // Yugoslavya ...) güncel bayrağı olmadığı için null döner, uygulama bayrak simgesi gösterir.
        public static string? Bayrak(string milliTakimIsim) =>
            UlkeKodlari.TryGetValue(milliTakimIsim, out var kod) ? $"https://flagcdn.com/w160/{kod}.png" : null;

        // ISO 3166 ülke kodları (flagcdn.com); İngiltere, İskoçya, Galler ve Kuzey İrlanda'nın kendi kodları var.
        // Olimpiyat, B ve genç takımlar ülkenin bayrağını kullanır.
        private static readonly IReadOnlyDictionary<string, string> UlkeKodlari = new Dictionary<string, string>
        {
            ["Afghanistan"] = "af", ["Albania"] = "al", ["Algeria"] = "dz", ["Andorra"] = "ad", ["Angola"] = "ao",
            ["Antigua and Barbuda"] = "ag", ["Argentina"] = "ar", ["Armenia"] = "am", ["Aruba"] = "aw", ["Australia"] = "au",
            ["Austria"] = "at", ["Azerbaijan"] = "az", ["Bahrain"] = "bh", ["Bangladesh"] = "bd", ["Barbados"] = "bb",
            ["Belarus"] = "by", ["Belgium"] = "be", ["Benin"] = "bj", ["Bermuda"] = "bm", ["Bolivia"] = "bo",
            ["Bosnia-Herzegovina"] = "ba", ["Brazil"] = "br", ["Bulgaria"] = "bg", ["Burkina Faso"] = "bf", ["Burundi"] = "bi",
            ["Cambodia"] = "kh", ["Cameroon"] = "cm", ["Canada"] = "ca", ["Cape Verde"] = "cv", ["Central African Republic"] = "cf",
            ["Chad"] = "td", ["Chile"] = "cl", ["China"] = "cn", ["Colombia"] = "co", ["Colombia Under 16"] = "co",
            ["Comoros"] = "km", ["Costa Rica"] = "cr", ["Croatia"] = "hr", ["Cuba"] = "cu", ["Curaçao"] = "cw",
            ["Cyprus"] = "cy", ["Czechia"] = "cz", ["Democratic Republic of the Congo"] = "cd", ["Denmark"] = "dk",
            ["Deutschland A2 (1999-2001)"] = "de", ["Dominican Republic"] = "do", ["Dominican Republic Olympia"] = "do",
            ["Dänische Liga-Auswahl"] = "dk", ["Ecuador"] = "ec", ["Egypt"] = "eg", ["El Salvador"] = "sv",
            ["England"] = "gb-eng", ["England C"] = "gb-eng", ["Equatorial Guinea"] = "gq", ["Eritrea"] = "er",
            ["Estonia"] = "ee", ["Ethiopia"] = "et", ["Faroe Islands"] = "fo", ["Finland"] = "fi", ["France"] = "fr",
            ["French Guiana"] = "gf", ["Gabon"] = "ga", ["Georgia"] = "ge", ["Germany"] = "de", ["Germany B (1951-1986)"] = "de",
            ["Germany Team 2006 (2001-2005)"] = "de", ["Ghana"] = "gh", ["Gibraltar"] = "gi", ["Great Britain"] = "gb",
            ["Greece"] = "gr", ["Grenada"] = "gd", ["Guadeloupe"] = "gp", ["Guam"] = "gu", ["Guatemala"] = "gt",
            ["Guinea"] = "gn", ["Guinea-Bissau"] = "gw", ["Guyana"] = "gy", ["Haiti"] = "ht", ["Honduras"] = "hn",
            ["Hungary"] = "hu", ["Iceland"] = "is", ["India"] = "in", ["Indonesia"] = "id", ["Iran"] = "ir", ["Iraq"] = "iq",
            ["Israel"] = "il", ["Italy"] = "it", ["Ivory Coast"] = "ci", ["Jamaica"] = "jm", ["Japan"] = "jp", ["Jordan"] = "jo",
            ["Kazakhstan"] = "kz", ["Kenya"] = "ke", ["Kosovo"] = "xk", ["Kyrgyzstan"] = "kg", ["Laos"] = "la", ["Latvia"] = "lv",
            ["Lebanon"] = "lb", ["Liberia"] = "lr", ["Libya"] = "ly", ["Liechtenstein"] = "li", ["Lithuania"] = "lt",
            ["Luxembourg"] = "lu", ["Madagascar"] = "mg", ["Malawi"] = "mw", ["Malaysia"] = "my", ["Mali"] = "ml",
            ["Mali Olympia"] = "ml", ["Malta"] = "mt", ["Martinique"] = "mq", ["Mauritania"] = "mr", ["Mauritius"] = "mu",
            ["Mexico"] = "mx", ["Moldova"] = "md", ["Montenegro"] = "me", ["Montserrat"] = "ms", ["Morocco"] = "ma",
            ["Mozambique"] = "mz", ["Namibia"] = "na", ["Netherlands"] = "nl", ["New Caledonia"] = "nc", ["New Zealand"] = "nz",
            ["Niger"] = "ne", ["Nigeria"] = "ng", ["North Korea"] = "kp", ["North Macedonia"] = "mk", ["Northern Ireland"] = "gb-nir",
            ["Norway"] = "no", ["Oman"] = "om", ["Pakistan"] = "pk", ["Palestine"] = "ps", ["Panama"] = "pa", ["Paraguay"] = "py",
            ["Paraguay Olympia"] = "py", ["Peru"] = "pe", ["Philippines"] = "ph", ["Poland"] = "pl", ["Portugal"] = "pt",
            ["Puerto Rico"] = "pr", ["Qatar"] = "qa", ["Republic of Ireland"] = "ie", ["Republic of the Congo"] = "cg",
            ["Romania"] = "ro", ["Russia"] = "ru", ["Rwanda"] = "rw", ["Réunion"] = "re", ["Saint Kitts and Nevis"] = "kn",
            ["Saint Lucia"] = "lc", ["Saint-Martin"] = "mf", ["San Marino"] = "sm", ["Saudi Arabia"] = "sa", ["Scotland"] = "gb-sct",
            ["Senegal"] = "sn", ["Senegal Olympia"] = "sn", ["Serbia"] = "rs", ["Seychelles"] = "sc", ["Sierra Leone"] = "sl",
            ["Slovakia"] = "sk", ["Slovenia"] = "si", ["Somalia"] = "so", ["South Africa"] = "za", ["South Korea"] = "kr",
            ["Spain"] = "es", ["Suriname"] = "sr", ["Sweden"] = "se", ["Switzerland"] = "ch", ["Syria"] = "sy",
            ["São Tomé and Príncipe"] = "st", ["Tahiti"] = "pf", ["Tajikistan"] = "tj", ["Tanzania"] = "tz", ["Thailand"] = "th",
            ["The Gambia"] = "gm", ["Togo"] = "tg", ["Trinidad and Tobago"] = "tt", ["Tunisia"] = "tn", ["Tunisia Olympia"] = "tn",
            ["Turkiye"] = "tr", ["Turks and Caicos Islands"] = "tc", ["Uganda"] = "ug", ["Ukraine"] = "ua",
            ["United Arab Emirates"] = "ae", ["United States"] = "us", ["Uruguay"] = "uy", ["Uruguay Olympia"] = "uy",
            ["Uzbekistan"] = "uz", ["Venezuela"] = "ve", ["Wales"] = "gb-wls", ["Yemen"] = "ye", ["Zambia"] = "zm",
            ["Zimbabwe"] = "zw",
        };
    }
}
