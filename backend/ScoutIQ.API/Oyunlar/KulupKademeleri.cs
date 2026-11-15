namespace ScoutIQ.API.Oyunlar
{
    // Kulüplerin kademesi (kulupler.kademe, 024_kulup_kademeleri.sql) ve Izgara ile Bingo'da nerede çıkabilecekleri.
    // Kademesi 'diger' ya da boş olan kulüpler bu oyunlarda başlık ya da kategori olmaz; oyuncuların o kulüplerdeki
    // kariyeri cevap olarak yine kabul edilir.
    public static class KulupKademeleri
    {
        public const string Buyuk = "buyuk";
        public const string BasAlti = "bas_alti";

        // Izgara: kolay tahtada sadece büyük kulüpler, orta ve zor tahtada büyük ve baş altı kulüpler
        public static bool IzgaradaCikar(string? kademe, Zorluk zorluk) =>
            kademe == Buyuk || (kademe == BasAlti && zorluk != Zorluk.Kolay);

        // Bingo: büyük ve baş altı kulüpler; kartta en fazla BingoSoruSecici.MaxBasAltiKulup baş altı kulüp olur
        public static bool BingodaCikar(string? kademe) => kademe is Buyuk or BasAlti;
    }
}
