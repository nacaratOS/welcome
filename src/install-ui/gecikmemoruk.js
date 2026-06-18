function gecikmemoruk(url) {
    document.body.style.opacity = '0';
    document.body.style.transform = 'scale(0.9)';

    // To Do: bu amk fonksiyonunu düzeltmeliyim
    // if (!selectedDisk) {
    //     alert('Lütfen bir disk seçin');
    //     return;
    // }

    setTimeout(function () {
        window.location.href = url;
    }, 1000);
}