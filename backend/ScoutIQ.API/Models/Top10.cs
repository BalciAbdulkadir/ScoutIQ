using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    // Oyuncunun bir transferi (004_transferler.sql). Top 10'un transfer soruları için sadece bedelli transferler okunur.
    [Table("transferler")]
    public class TransferKaydi : BaseModel
    {
        [PrimaryKey("id", false)]
        public string Id { get; set; } = string.Empty;

        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        [Column("eski_kulup_tm_id")]
        public string? EskiKulupTmId { get; set; }

        [Column("yeni_kulup_tm_id")]
        public string? YeniKulupTmId { get; set; }

        [Column("tarih")]
        public DateTime? Tarih { get; set; }

        // Transfermarkt biçiminde, ör. '18/19'
        [Column("sezon")]
        public string? Sezon { get; set; }

        // transfer, loan, freeTransfer, endOfLoan ...
        [Column("tip")]
        public string Tip { get; set; } = string.Empty;

        // Euro; null: bedel yok ya da bilinmiyor
        [Column("bedel")]
        public long? Bedel { get; set; }
    }

    // Bir yılın Ballon d'Or sıralamasındaki bir aday (028_ballon_dor.sql)
    [Table("ballon_dor_siralamalari")]
    public class BallonDorSiralamasi : BaseModel
    {
        [PrimaryKey("id", false)]
        public long Id { get; set; }

        [Column("yil")]
        public int Yil { get; set; }

        [Column("sira")]
        public int Sira { get; set; }

        // Veritabanında olmayan oyuncuda null
        [Column("oyuncu_id")]
        public string? OyuncuId { get; set; }

        [Column("puan")]
        public decimal? Puan { get; set; }

        // Sadece 2010-2015 (FIFA Ballon d'Or): oy yüzdesi
        [Column("yuzde")]
        public decimal? Yuzde { get; set; }
    }

    // Top 10'un bir günkü sorusunun şablonu ve değişkeni (029_top10.sql). Uygulamaya kapalıdır.
    [Table("top10_sorulari")]
    public class Top10SorusuKaydi : BaseModel
    {
        [PrimaryKey("oyun_id", true)]
        public string OyunId { get; set; } = string.Empty;

        [Column("tarih")]
        public DateTime Tarih { get; set; }

        [Column("sablon")]
        public string Sablon { get; set; } = string.Empty;

        [Column("anahtar")]
        public string Anahtar { get; set; } = string.Empty;

        [Column("eksen")]
        public string Eksen { get; set; } = string.Empty;
    }

    // Top 10'un bir günkü cevap listesindeki bir satır (029_top10.sql). Uygulamaya kapalıdır.
    [Table("top10_cevaplari")]
    public class Top10Cevabi : BaseModel
    {
        [Column("oyun_id")]
        public string OyunId { get; set; } = string.Empty;

        [Column("sira")]
        public int Sira { get; set; }

        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        [Column("oyuncu_isim")]
        public string OyuncuIsim { get; set; } = string.Empty;

        [Column("deger")]
        public string Deger { get; set; } = string.Empty;
    }
}
