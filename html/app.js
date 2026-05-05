const menu = document.getElementById('power-menu');
const closeBtn = document.getElementById('close-btn');
const powerCards = document.querySelectorAll('.power-card');

let selectedPower = 'none';

function openMenu(selected) {
    selectedPower = selected || 'none';
    menu.classList.add('active');
    setSelected(selectedPower);
}

function closeMenu() {
    menu.classList.remove('active');

    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    });
}

function setSelected(power) {
    selectedPower = power || 'none';

    powerCards.forEach((card) => {
        const button = card.querySelector('button');

        if (card.dataset.power === selectedPower) {
            card.classList.add('selected');
            button.innerText = 'Seçili';
        } else {
            card.classList.remove('selected');
            button.innerText = 'Seç';
        }
    });
}

window.addEventListener('message', function(event) {
    const data = event.data;

    if (!data) return;

    if (data.action === 'open') {
        openMenu(data.selected);
    }

    if (data.action === 'close') {
        menu.classList.remove('active');
    }

    if (data.action === 'setSelected') {
        setSelected(data.selected);
    }
});

powerCards.forEach((card) => {
    card.addEventListener('click', () => {
        const power = card.dataset.power;

        fetch(`https://${GetParentResourceName()}/selectPower`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                power: power
            })
        });
    });
});

closeBtn.addEventListener('click', closeMenu);

document.addEventListener('keyup', function(e) {
    if (e.key === 'Escape') {
        closeMenu();
    }
});