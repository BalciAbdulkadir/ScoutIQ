using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    [Table("oyuncular")]
    public class Oyuncu : BaseModel
    {
        [PrimaryKey("id", false)]
        public string Id { get; set; } = string.Empty;

        [Column("isim")]
        public string Isim { get; set; } = string.Empty;

        [Column("toplam_bonservis")]
        public long ToplamBonservis { get; set; }

        // Transfermarkt'taki fotoğrafın adresi, fotoğrafı olmayan oyuncularda null
        [Column("foto_url")]
        public string? FotoUrl { get; set; }

        // Soru havuzundaki kademe: unlu, bilinen, diger, cevap ya da null (data_miner/kademeler.py)
        [Column("kademe")]
        public string? Kademe { get; set; }

        // Elle düzeltme: doluysa kademe yerine bu geçerlidir
        [Column("kademe_override")]
        public string? KademeOverride { get; set; }
    }
}
