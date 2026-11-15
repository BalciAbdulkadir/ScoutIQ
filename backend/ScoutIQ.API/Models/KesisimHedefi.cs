using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    // Kolay Kesişim'in bir sorusunun hedef oyuncusu ve kulüp çifti (027_kesisim_hedefleri.sql).
    // Uygulamaya kapalıdır: tekrar kuralları için sadece backend okur ve yazar.
    [Table("kesisim_hedefleri")]
    public class KesisimHedefi : BaseModel
    {
        // Veritabanı üretir; okurken sayfalama için kullanılır
        [PrimaryKey("id", false)]
        public long Id { get; set; }

        [Column("oyun_id")]
        public string OyunId { get; set; } = string.Empty;

        // Sorunun oyundaki sırası, 1'den başlar
        [Column("sira")]
        public int Sira { get; set; }

        [Column("tarih")]
        public DateTime Tarih { get; set; }

        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        // Çift sırasızdır: kulup_a_id her zaman küçük olandır
        [Column("kulup_a_id")]
        public string KulupAId { get; set; } = string.Empty;

        [Column("kulup_b_id")]
        public string KulupBId { get; set; } = string.Empty;
    }
}
