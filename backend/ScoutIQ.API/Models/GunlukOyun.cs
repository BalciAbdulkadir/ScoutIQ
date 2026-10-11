using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    [Table("gunluk_oyunlar")]
    public class GunlukOyun : BaseModel
    {
        [PrimaryKey("id", false)]
        public string Id { get; set; } = string.Empty;

        [Column("oyun_tipi")]
        public string OyunTipi { get; set; } = string.Empty;

        [Column("tarih")]
        public DateTime Tarih { get; set; }

        // object kullanıyoruz ki C# bunu otomatik olarak JSONB'ye çevirip Supabase'e fırlatsın
        [Column("soru_verisi")]
        public object SoruVerisi { get; set; } = null!;
    }
}
