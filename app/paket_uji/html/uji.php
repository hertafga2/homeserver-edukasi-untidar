<?php
// Halaman uji dinamis: setiap permintaan membaca dan mengurutkan data dari basis data.
// Host basis data = nama layanan 'db' pada docker-compose.yml.
$db = new mysqli('db', 'uji', 'gantiSandiIni', 'uji_homeserver');
if ($db->connect_errno) {
    http_response_code(500);
    exit('Koneksi basis data gagal');
}
$ringkas = $db->query('SELECT COUNT(*) AS n, AVG(nilai) AS rata FROM mahasiswa')->fetch_assoc();
$hasil = $db->query('SELECT nim, nama, nilai FROM mahasiswa ORDER BY nilai DESC, id LIMIT 50');
?>
<!doctype html>
<html lang="id">
<head><meta charset="utf-8"><title>Uji Halaman Dinamis</title></head>
<body>
<h1>Daftar Nilai</h1>
<p>Jumlah data: <?= $ringkas['n'] ?>; rata-rata nilai: <?= number_format((float) $ringkas['rata'], 2) ?></p>
<table>
<tr><th>NIM</th><th>Nama</th><th>Nilai</th></tr>
<?php while ($r = $hasil->fetch_assoc()): ?>
<tr><td><?= htmlspecialchars($r['nim']) ?></td><td><?= htmlspecialchars($r['nama']) ?></td><td><?= $r['nilai'] ?></td></tr>
<?php endwhile; ?>
</table>
</body>
</html>
