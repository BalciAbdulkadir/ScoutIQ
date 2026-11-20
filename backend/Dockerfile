# ScoutIQ soru üretim işi (Google Cloud Run Jobs). Kurulum: backend/CLOUD_RUN.md
# backend klasöründen derlenir:  docker build -t scoutiq-uretim backend
# İmajda sadece API projesi vardır; test projesi, derleme çıktıları ve gizli anahtar girmez (.dockerignore).
# Supabase secret anahtarı çalışırken Supabase__Key ortam değişkeniyle verilir (Secret Manager).

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS derleme
WORKDIR /src
COPY ScoutIQ.API/ScoutIQ.API.csproj ScoutIQ.API/
RUN dotnet restore ScoutIQ.API/ScoutIQ.API.csproj
COPY ScoutIQ.API/ ScoutIQ.API/
RUN dotnet publish ScoutIQ.API/ScoutIQ.API.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/runtime:10.0
# Kod Europe/Istanbul saat dilimini kullanır (oyun günü Türkiye saatine göredir). .NET saat dilimi verisini işletim
# sisteminden okur: tzdata'nın imajda olduğundan emin olunur, yoksa program açılırken hata verir.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=derleme /app .
USER $APP_UID
ENTRYPOINT ["dotnet", "ScoutIQ.API.dll"]
