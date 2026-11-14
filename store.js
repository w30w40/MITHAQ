(() => {
  const STORE_BUCKET = 'mithaq-store';
  const STORE_WHATSAPP = '966543590926';
  let storeItems = [];
  let storeEditingImages = [];
  let storeIsAdmin = false;
  let currentStoreDetailIndex = -1;
  let storeDetailReturnFocus = null;

  const el = (tag, className, value) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (value !== undefined && value !== null) node.textContent = String(value);
    return node;
  };
  const storePublicUrl = path => supabaseClient.storage.from(STORE_BUCKET).getPublicUrl(path).data.publicUrl;
  const storeMoney = item => {
    if (item.price === null || item.price === undefined) return 'السعر عند الاستفسار';
    try { return new Intl.NumberFormat('ar', { style: 'currency', currency: item.currency || 'SAR', maximumFractionDigits: 2 }).format(Number(item.price)); }
    catch (_) { return String(item.price) + ' ' + (item.currency || ''); }
  };
  const storeStatus = item => item.availability_status === 'available' ? 'متوفر' : 'غير متوفر';

  function createStorePage() {
    if (document.getElementById('store')) return;
    const main = document.querySelector('main');
    const bottom = document.getElementById('mithaqBottomNav');
    if (!main || !bottom) return;
    const section = el('section');
    section.id = 'store';
    section.className = 'tab hidden';
    section.dir = 'rtl';
    section.innerHTML = `
      <button type="button" class="mithaq-section-back" id="mithaqStoreBack">← رجوع</button>
      <div class="mithaq-store-heading">
        <div><span class="member-eyebrow">MITHAQ • STORE</span><h1>متجر ميثاق</h1><p>تصفّح المعروضات والعروض المنشورة من إدارة ميثاق</p></div>
        <span class="mithaq-store-mark" aria-hidden="true">🛍️</span>
      </div>
      <div id="mithaqStoreAdmin" class="card mithaq-store-admin" hidden>
        <div class="mithaq-store-section-title"><div><h2>إدارة المتجر</h2><p>إضافة المعروضات وتعديلها ونشرها أو إخفاؤها</p></div><span class="mithaq-store-admin-tag">الإدارة فقط</span></div>
        <form id="mithaqStoreForm">
          <input id="mithaqStoreEditId" type="hidden">
          <label class="mithaq-store-field">اسم المعروض<input id="mithaqStoreTitle" type="text" maxlength="180" required placeholder="اكتب اسم المعروض"></label>
          <label class="mithaq-store-field">الوصف الكامل<textarea id="mithaqStoreDescription" rows="4" maxlength="12000" required placeholder="اكتب وصف المعروض بالتفصيل"></textarea></label>
          <label class="mithaq-store-field">المواصفات والتفاصيل<textarea id="mithaqStoreSpecifications" rows="4" maxlength="12000" placeholder="المقاسات، النوع، المميزات، تفاصيل الخدمة أو أي معلومات إضافية"></textarea></label>
          <div class="mithaq-store-form-grid">
            <label class="mithaq-store-field">السعر<input id="mithaqStorePrice" type="number" min="0" step="0.01" placeholder="اتركه فارغاً إذا لم يحدد السعر"></label>
            <label class="mithaq-store-field">العملة<input id="mithaqStoreCurrency" type="text" maxlength="3" value="SAR" required></label>
            <label class="mithaq-store-field">حالة المعروض<select id="mithaqStoreAvailability"><option value="available">متوفر</option><option value="unavailable">غير متوفر</option></select></label>
          </div>
          <label class="mithaq-store-field">صور المعروض (حتى 10 صور، JPG أو PNG أو WEBP أو GIF)<input id="mithaqStoreImages" type="file" accept="image/jpeg,image/png,image/webp,image/gif" multiple></label>
          <div id="mithaqStoreExistingImages" class="mithaq-store-image-admin-list"></div>
          <label class="mithaq-store-publish"><input id="mithaqStorePublished" type="checkbox" checked> نشر المعروض وإظهاره للأعضاء</label>
          <div class="mithaq-store-form-actions"><button id="mithaqStoreSave" class="primary" type="submit">حفظ المعروض</button><button id="mithaqStoreCancelEdit" class="secondary" type="button" hidden>إلغاء التعديل</button></div>
          <p id="mithaqStoreAdminStatus" class="notice" role="status" aria-live="polite"></p>
        </form>
      </div>
      <div class="mithaq-store-list-heading"><h2>المعروضات</h2><span id="mithaqStoreCount"></span></div>
      <p id="mithaqStoreStatus" class="muted" role="status" aria-live="polite">جارٍ تحميل المتجر...</p>
      <div id="mithaqStoreGrid" class="mithaq-store-grid"></div>
      <div id="mithaqStoreDetail" class="mithaq-store-overlay mithaq-store-detail-overlay" hidden>
        <div class="mithaq-store-dialog mithaq-store-detail-dialog" role="dialog" aria-modal="true" aria-labelledby="mithaqStoreDetailTitle" tabindex="-1">
          <div class="mithaq-store-detail-toolbar">
            <button type="button" id="mithaqStoreDetailClose" class="mithaq-store-detail-back" aria-label="العودة إلى قائمة المعروضات">← العودة للمتجر</button>
            <div class="mithaq-store-detail-pagination" aria-label="التنقل بين المعروضات">
              <button type="button" id="mithaqStoreDetailPrevious" class="secondary" aria-label="المعروض السابق">السابق</button>
              <button type="button" id="mithaqStoreDetailNext" class="secondary" aria-label="المعروض التالي">التالي</button>
            </div>
          </div>
          <div id="mithaqStoreDetailContent" class="mithaq-store-detail-content"></div>
        </div>
      </div>
      <div id="mithaqStoreConsent" class="mithaq-store-overlay" hidden>
        <div class="mithaq-store-dialog mithaq-store-consent-dialog" role="dialog" aria-modal="true" aria-labelledby="mithaqStoreConsentTitle">
          <button type="button" id="mithaqStoreConsentClose" class="mithaq-store-close" aria-label="إغلاق">×</button>
          <h2 id="mithaqStoreConsentTitle">مراجعة رسالة واتساب</h2>
          <p class="mithaq-store-privacy-note">ستتضمن الرسالة معلومات المعروض، وبيانات حسابك التالية عند توفرها: الاسم والبريد الإلكتروني ورقم العضوية ورقم الهاتف. لن تظهر هذه البيانات للأعضاء الآخرين. ستنتقل الرسالة إلى واتساب لتراجعها بنفسك؛ ولن تُرسل إلا إذا ضغطت زر «إرسال» داخل واتساب.</p>
          <label class="mithaq-store-field">الرسالة الجاهزة (يمكنك تعديلها قبل فتح واتساب)<textarea id="mithaqStoreWhatsAppMessage" rows="13" maxlength="12000"></textarea></label>
          <label class="mithaq-store-consent-check"><input id="mithaqStoreWhatsAppConsent" type="checkbox"> أوافق على تضمين بيانات حسابي الموضحة أعلاه في رسالة واتساب الموجهة إلى إدارة ميثاق.</label>
          <div class="mithaq-store-form-actions"><button type="button" id="mithaqStoreWhatsAppContinue" class="primary" disabled>فتح واتساب ومراجعة الرسالة</button><button type="button" id="mithaqStoreWhatsAppCancel" class="secondary">إلغاء</button></div>
          <p class="mithaq-store-whatsapp-fallback-note">إذا لم يفتح تطبيق واتساب تلقائياً، استخدم أحد الخيارين التاليين:</p>
          <div class="mithaq-store-form-actions mithaq-store-whatsapp-fallback-actions">
            <a id="mithaqStoreWhatsAppAppLink" class="secondary mithaq-store-whatsapp-link is-disabled" aria-disabled="true">محاولة فتح تطبيق واتساب مباشرة</a>
            <a id="mithaqStoreWhatsAppWebLink" class="secondary mithaq-store-whatsapp-link is-disabled" aria-disabled="true">المتابعة عبر wa.me في المتصفح</a>
          </div>
        </div>
      </div>`;
    main.append(section);
    const navButton = el('button');
    navButton.type = 'button';
    navButton.dataset.bottomGo = 'store';
    navButton.setAttribute('aria-label', 'متجر');
    navButton.innerHTML = '<span class="bottom-icon">🛍️</span><span>متجر</span>';
    bottom.append(navButton);
    navButton.addEventListener('click', () => {
      show('store');
      loadMithaqStore();
    });
    document.getElementById('mithaqStoreBack').addEventListener('click', () => goBack());
    document.getElementById('mithaqStoreDetailClose').addEventListener('click', closeStoreDetail);
    document.getElementById('mithaqStoreDetailPrevious').addEventListener('click', () => moveStoreDetail(-1));
    document.getElementById('mithaqStoreDetailNext').addEventListener('click', () => moveStoreDetail(1));
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && !document.getElementById('mithaqStoreDetail').hidden) closeStoreDetail();
    });
    document.getElementById('mithaqStoreConsentClose').addEventListener('click', closeStoreConsent);
    document.getElementById('mithaqStoreWhatsAppCancel').addEventListener('click', closeStoreConsent);
    document.getElementById('mithaqStoreWhatsAppConsent').addEventListener('change', event => {
      document.getElementById('mithaqStoreWhatsAppContinue').disabled = !event.target.checked;
      updateStoreWhatsAppLinks();
    });
    document.getElementById('mithaqStoreWhatsAppMessage').addEventListener('input', updateStoreWhatsAppLinks);
    document.getElementById('mithaqStoreWhatsAppAppLink').addEventListener('click', event => {
      if (!document.getElementById('mithaqStoreWhatsAppConsent').checked) event.preventDefault();
    });
    document.getElementById('mithaqStoreWhatsAppWebLink').addEventListener('click', event => {
      if (!document.getElementById('mithaqStoreWhatsAppConsent').checked) event.preventDefault();
    });
    document.getElementById('mithaqStoreWhatsAppContinue').addEventListener('click', continueStoreWhatsApp);
    document.getElementById('mithaqStoreForm').addEventListener('submit', saveStoreItem);
    document.getElementById('mithaqStoreCancelEdit').addEventListener('click', resetStoreForm);
    document.getElementById('mithaqStoreDetail').addEventListener('click', event => {
      if (event.target.id === 'mithaqStoreDetail') closeStoreDetail();
    });
    document.getElementById('mithaqStoreConsent').addEventListener('click', event => {
      if (event.target.id === 'mithaqStoreConsent') closeStoreConsent();
    });
  }

  async function loadMithaqStore() {
    const status = document.getElementById('mithaqStoreStatus');
    const grid = document.getElementById('mithaqStoreGrid');
    const adminPanel = document.getElementById('mithaqStoreAdmin');
    if (!status || !grid || !supabaseClient) return;
    status.textContent = 'جارٍ تحميل المعروضات...';
    grid.replaceChildren();
    const { data: authData, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !authData?.user) {
      status.textContent = 'سجّل الدخول أولاً لعرض متجر ميثاق.';
      if (adminPanel) adminPanel.hidden = true;
      return;
    }
    storeIsAdmin = await refreshMithaqAdminAccess();
    if (adminPanel) adminPanel.hidden = !storeIsAdmin;
    const { data: items, error } = await supabaseClient.from('mithaq_store_items').select('*').order('created_at', { ascending: false });
    if (error) {
      status.textContent = 'تعذر تحميل المتجر: ' + error.message;
      return;
    }
    const ids = (items || []).map(item => item.id);
    let images = [];
    if (ids.length) {
      const imageResult = await supabaseClient.from('mithaq_store_images').select('*').in('item_id', ids).order('sort_order', { ascending: true });
      if (imageResult.error) {
        status.textContent = 'تعذر تحميل صور المعروضات: ' + imageResult.error.message;
        return;
      }
      images = imageResult.data || [];
    }
    const byItem = new Map();
    images.forEach(image => {
      if (!byItem.has(image.item_id)) byItem.set(image.item_id, []);
      byItem.get(image.item_id).push(image);
    });
    storeItems = (items || []).map(item => ({ ...item, images: byItem.get(item.id) || [] }));
    document.getElementById('mithaqStoreCount').textContent = storeItems.length + ' معروض';
    renderStoreCards();
    status.textContent = storeItems.length ? 'تظهر هنا المعروضات المنشورة من إدارة ميثاق.' : (storeIsAdmin ? 'المتجر فارغ حالياً. يمكنك إضافة أول معروض من لوحة إدارة المتجر.' : 'لا توجد معروضات منشورة حالياً.');
  }

  function renderStoreCards() {
    const host = document.getElementById('mithaqStoreGrid');
    if (!host) return;
    host.replaceChildren();
    storeItems.forEach(item => {
      const card = el('article', 'mithaq-store-card');
      const firstImage = item.images?.[0];
      if (firstImage) {
        const image = el('img', 'mithaq-store-card-image');
        image.src = storePublicUrl(firstImage.object_path);
        image.alt = firstImage.alt_text || item.title;
        image.loading = 'lazy';
        card.append(image);
      } else {
        card.append(el('div', 'mithaq-store-no-image', '🛍️'));
      }
      const body = el('div', 'mithaq-store-card-body');
      body.append(el('h3', '', item.title));
      body.append(el('p', 'mithaq-store-card-description', item.description));
      const meta = el('div', 'mithaq-store-card-meta');
      meta.append(el('span', 'mithaq-store-price', storeMoney(item)));
      meta.append(el('span', 'mithaq-store-status' + (item.availability_status === 'available' ? '' : ' unavailable'), storeStatus(item)));
      body.append(meta);
      const actions = el('div', 'mithaq-store-card-actions');
      const details = el('button', 'secondary', 'عرض التفاصيل');
      details.type = 'button';
      details.addEventListener('click', () => openStoreDetail(item));
      const contact = el('button', 'mithaq-store-contact', 'تواصل عبر الإدارة على واتساب');
      contact.type = 'button';
      contact.addEventListener('click', () => prepareStoreWhatsApp(item));
      actions.append(details, contact);
      body.append(actions);
      if (storeIsAdmin) {
        if (!item.is_published) body.append(el('span', 'mithaq-store-status hidden-item', 'مخفي عن الأعضاء'));
        const adminActions = el('div', 'mithaq-store-admin-actions');
        const edit = el('button', 'secondary', 'تعديل');
        edit.type = 'button';
        edit.addEventListener('click', () => editStoreItem(item));
        const remove = el('button', 'secondary', 'حذف');
        remove.type = 'button';
        remove.addEventListener('click', () => deleteStoreItem(item));
        adminActions.append(edit, remove);
        body.append(adminActions);
      }
      card.append(body);
      host.append(card);
    });
  }

  function renderStoreDetail(item) {
    const host = document.getElementById('mithaqStoreDetailContent');
    host.replaceChildren();
    const title = el('h2', 'mithaq-store-detail-title', item.title);
    title.id = 'mithaqStoreDetailTitle';
    host.append(title);
    host.append(el('p', 'mithaq-store-card-meta', 'رقم العرض: ' + item.item_number));
    const gallery = el('div', 'mithaq-store-detail-gallery');
    (item.images || []).forEach(image => {
      const img = el('img');
      img.src = storePublicUrl(image.object_path);
      img.alt = image.alt_text || item.title;
      img.loading = 'lazy';
      gallery.append(img);
    });
    if (gallery.childElementCount) host.append(gallery);
    host.append(el('h3', '', 'الوصف'));
    host.append(el('p', 'mithaq-store-detail-text', item.description));
    if (item.specifications) {
      host.append(el('h3', '', 'المواصفات والتفاصيل'));
      host.append(el('p', 'mithaq-store-detail-text', item.specifications));
    }
    host.append(el('p', 'mithaq-store-price', 'السعر: ' + storeMoney(item)));
    host.append(el('p', 'mithaq-store-status' + (item.availability_status === 'available' ? '' : ' unavailable'), 'الحالة: ' + storeStatus(item)));
    const contact = el('button', 'primary mithaq-store-contact mithaq-store-detail-contact', 'تواصل عبر الإدارة على واتساب');
    contact.type = 'button';
    contact.addEventListener('click', () => prepareStoreWhatsApp(item));
    host.append(contact);

    document.getElementById('mithaqStoreDetailPrevious').disabled = currentStoreDetailIndex <= 0;
    document.getElementById('mithaqStoreDetailNext').disabled = currentStoreDetailIndex >= storeItems.length - 1;
  }

  function openStoreDetail(item) {
    currentStoreDetailIndex = storeItems.findIndex(row => row.id === item.id);
    if (currentStoreDetailIndex < 0) return;
    storeDetailReturnFocus = document.activeElement;
    renderStoreDetail(storeItems[currentStoreDetailIndex]);
    const overlay = document.getElementById('mithaqStoreDetail');
    overlay.hidden = false;
    document.body.classList.add('mithaq-store-detail-open');
    const dialog = overlay.querySelector('.mithaq-store-detail-dialog');
    dialog.scrollTop = 0;
    dialog.focus({ preventScroll: true });
  }

  function moveStoreDetail(direction) {
    const nextIndex = currentStoreDetailIndex + direction;
    if (nextIndex < 0 || nextIndex >= storeItems.length) return;
    currentStoreDetailIndex = nextIndex;
    renderStoreDetail(storeItems[currentStoreDetailIndex]);
    const dialog = document.querySelector('#mithaqStoreDetail .mithaq-store-detail-dialog');
    if (dialog) dialog.scrollTop = 0;
  }

  function closeStoreDetail() {
    const overlay = document.getElementById('mithaqStoreDetail');
    if (!overlay) return;
    overlay.hidden = true;
    document.body.classList.remove('mithaq-store-detail-open');
    currentStoreDetailIndex = -1;
    if (storeDetailReturnFocus && document.contains(storeDetailReturnFocus)) {
      storeDetailReturnFocus.focus({ preventScroll: true });
    }
  }

  async function prepareStoreWhatsApp(item) {
    const status = document.getElementById('mithaqStoreStatus');
    const { data: authData, error: authError } = await supabaseClient.auth.getUser();
    const user = authData?.user;
    if (authError || !user) {
      status.textContent = 'يجب تسجيل الدخول أولاً للتواصل مع الإدارة.';
      return;
    }
    const [profileResult, detailsResult] = await Promise.all([
      supabaseClient.from('profiles').select('display_name,member_number').eq('id', user.id).maybeSingle(),
      supabaseClient.from('profile_details').select('details').eq('id', user.id).maybeSingle()
    ]);
    if (profileResult.error || detailsResult.error) {
      status.textContent = 'تعذر قراءة بيانات حسابك الخاصة. لم يتم فتح واتساب.';
      return;
    }
    const profile = profileResult.data || {};
    const details = detailsResult.data?.details || {};
    const memberName = details.full_name || user.user_metadata?.full_name || profile.display_name || details.username || '';
    const phone = details.phone_number || user.phone || '';
    const lines = [
      'السلام عليكم ورحمة الله وبركاته،',
      '',
      'لدي استفسار أو طلب بخصوص عرض منشور في متجر ميثاق.',
      '',
      'معلومات العرض:',
      'اسم العرض: ' + item.title,
      'تفاصيل العرض: ' + item.description,
      item.specifications ? 'المواصفات والتفاصيل: ' + item.specifications : '',
      'السعر: ' + (item.price === null || item.price === undefined ? 'لم تحدده الإدارة' : storeMoney(item)),
      'رقم العرض: ' + item.item_number,
      '',
      'معلومات العضو:',
      memberName ? 'الاسم: ' + memberName : '',
      user.email ? 'البريد الإلكتروني: ' + user.email : '',
      profile.member_number !== null && profile.member_number !== undefined ? 'رقم العضوية: ' + profile.member_number : '',
      phone ? 'رقم الهاتف: ' + phone : '',
      '',
      'أرغب بالتواصل مع الإدارة بخصوص هذا العرض.',
      '',
      'شكراً لكم.'
    ].filter(line => line !== '');
    document.getElementById('mithaqStoreWhatsAppMessage').value = lines.join('\n');
    document.getElementById('mithaqStoreWhatsAppConsent').checked = false;
    document.getElementById('mithaqStoreWhatsAppContinue').disabled = true;
    closeStoreDetail();
    document.getElementById('mithaqStoreConsent').hidden = false;
  }

  function closeStoreConsent() {
    document.getElementById('mithaqStoreConsent').hidden = true;
    document.getElementById('mithaqStoreWhatsAppConsent').checked = false;
    document.getElementById('mithaqStoreWhatsAppContinue').disabled = true;
    ['mithaqStoreWhatsAppAppLink', 'mithaqStoreWhatsAppWebLink'].forEach(id => {
      const link = document.getElementById(id);
      link.removeAttribute('href');
      link.classList.add('is-disabled');
      link.setAttribute('aria-disabled', 'true');
    });
  }
  function updateStoreWhatsAppLinks() {
    const allowed = document.getElementById('mithaqStoreWhatsAppConsent').checked;
    const message = document.getElementById('mithaqStoreWhatsAppMessage').value.trim();
    const encodedMessage = encodeURIComponent(message);
    const appLink = document.getElementById('mithaqStoreWhatsAppAppLink');
    const webLink = document.getElementById('mithaqStoreWhatsAppWebLink');
    [appLink, webLink].forEach(link => {
      link.classList.toggle('is-disabled', !allowed || !message);
      link.setAttribute('aria-disabled', String(!allowed || !message));
      if (!allowed || !message) link.removeAttribute('href');
    });
    if (allowed && message) {
      appLink.href = 'whatsapp://send?phone=' + STORE_WHATSAPP + '&text=' + encodedMessage;
      webLink.href = 'https://wa.me/' + STORE_WHATSAPP + '?text=' + encodedMessage;
    }
  }

  function continueStoreWhatsApp() {
    if (!document.getElementById('mithaqStoreWhatsAppConsent').checked) return;
    const message = document.getElementById('mithaqStoreWhatsAppMessage').value.trim();
    if (!message) return;
    const encodedMessage = encodeURIComponent(message);
    const url = 'https://wa.me/' + STORE_WHATSAPP + '?text=' + encodedMessage;
    // Same-tab navigation allows Android App Links to hand wa.me to the installed WhatsApp app.
    // Avoid window.open(), which commonly leaves the user in a browser tab.
    window.location.assign(url);
  }

  function renderStoreExistingImages() {
    const host = document.getElementById('mithaqStoreExistingImages');
    host.replaceChildren();
    storeEditingImages.forEach(image => {
      const wrap = el('div', 'mithaq-store-image-admin');
      const img = el('img');
      img.src = storePublicUrl(image.object_path);
      img.alt = image.alt_text || 'صورة المعروض';
      const remove = el('button', 'secondary', 'إزالة الصورة');
      remove.type = 'button';
      remove.addEventListener('click', async () => {
        if (!confirm('هل تريد إزالة هذه الصورة من المعروض؟')) return;
        remove.disabled = true;
        const { error: storageError } = await supabaseClient.storage.from(STORE_BUCKET).remove([image.object_path]);
        if (storageError) { alert('تعذر حذف ملف الصورة: ' + storageError.message); remove.disabled = false; return; }
        const { error } = await supabaseClient.from('mithaq_store_images').delete().eq('id', image.id);
        if (error) { alert('تعذر تحديث بيانات الصورة: ' + error.message); remove.disabled = false; return; }
        storeEditingImages = storeEditingImages.filter(row => row.id !== image.id);
        renderStoreExistingImages();
      });
      wrap.append(img, remove);
      host.append(wrap);
    });
  }

  function editStoreItem(item) {
    document.getElementById('mithaqStoreEditId').value = item.id;
    document.getElementById('mithaqStoreTitle').value = item.title || '';
    document.getElementById('mithaqStoreDescription').value = item.description || '';
    document.getElementById('mithaqStoreSpecifications').value = item.specifications || '';
    document.getElementById('mithaqStorePrice').value = item.price ?? '';
    document.getElementById('mithaqStoreCurrency').value = item.currency || 'SAR';
    document.getElementById('mithaqStoreAvailability').value = item.availability_status || 'available';
    document.getElementById('mithaqStorePublished').checked = !!item.is_published;
    document.getElementById('mithaqStoreImages').value = '';
    storeEditingImages = [...(item.images || [])];
    renderStoreExistingImages();
    document.getElementById('mithaqStoreSave').textContent = 'حفظ التعديلات';
    document.getElementById('mithaqStoreCancelEdit').hidden = false;
    document.getElementById('mithaqStoreAdminStatus').textContent = 'تعديل المعروض رقم ' + item.item_number;
    document.getElementById('mithaqStoreAdmin').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function resetStoreForm() {
    document.getElementById('mithaqStoreForm').reset();
    document.getElementById('mithaqStoreEditId').value = '';
    document.getElementById('mithaqStoreCurrency').value = 'SAR';
    document.getElementById('mithaqStorePublished').checked = true;
    document.getElementById('mithaqStoreImages').value = '';
    storeEditingImages = [];
    renderStoreExistingImages();
    document.getElementById('mithaqStoreSave').textContent = 'حفظ المعروض';
    document.getElementById('mithaqStoreCancelEdit').hidden = true;
    document.getElementById('mithaqStoreAdminStatus').textContent = '';
  }

  async function saveStoreItem(event) {
    event.preventDefault();
    const status = document.getElementById('mithaqStoreAdminStatus');
    const button = document.getElementById('mithaqStoreSave');
    const allowed = await refreshMithaqAdminAccess();
    if (!allowed) { status.textContent = 'ليس لديك صلاحية إدارة المتجر.'; return; }
    const { data: authData, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !authData?.user) { status.textContent = 'انتهت جلسة الدخول. سجّل الدخول مجدداً.'; return; }
    const title = document.getElementById('mithaqStoreTitle').value.trim();
    const description = document.getElementById('mithaqStoreDescription').value.trim();
    const specifications = document.getElementById('mithaqStoreSpecifications').value.trim();
    const priceRaw = document.getElementById('mithaqStorePrice').value.trim();
    const price = priceRaw === '' ? null : Number(priceRaw);
    const currency = document.getElementById('mithaqStoreCurrency').value.trim().toUpperCase();
    const availability = document.getElementById('mithaqStoreAvailability').value;
    const published = document.getElementById('mithaqStorePublished').checked;
    const files = Array.from(document.getElementById('mithaqStoreImages').files || []);
    const editId = document.getElementById('mithaqStoreEditId').value;
    if (title.length < 2 || !description) { status.textContent = 'أدخل اسم المعروض والوصف الكامل.'; return; }
    if (price !== null && (!Number.isFinite(price) || price < 0)) { status.textContent = 'السعر غير صحيح.'; return; }
    if (!/^[A-Z]{3}$/.test(currency)) { status.textContent = 'رمز العملة يجب أن يتكون من ثلاثة أحرف مثل SAR.'; return; }
    if (storeEditingImages.length + files.length < 1) { status.textContent = 'أضف صورة واحدة على الأقل للمعروض.'; return; }
    if (storeEditingImages.length + files.length > 10) { status.textContent = 'الحد الأقصى عشر صور لكل معروض.'; return; }
    const allowedTypes = ['image/jpeg','image/png','image/webp','image/gif'];
    if (files.some(file => !allowedTypes.includes(file.type) || file.size > 10 * 1024 * 1024)) {
      status.textContent = 'تأكد أن كل صورة JPG أو PNG أو WEBP أو GIF وحجمها لا يتجاوز 10 ميغابايت.';
      return;
    }
    button.disabled = true;
    status.textContent = 'جارٍ حفظ المعروض ورفع الصور...';
    let itemId = editId;
    const isNew = !editId;
    const payload = {
      title, description, specifications, price, currency,
      availability_status: availability,
      updated_at: new Date().toISOString()
    };
    if (isNew) {
      const { data, error } = await supabaseClient.from('mithaq_store_items')
        .insert({ ...payload, is_published: false, created_by: authData.user.id })
        .select('id').single();
      if (error) {
        status.textContent = 'تعذر إنشاء المعروض: ' + error.message;
        button.disabled = false;
        return;
      }
      itemId = data.id;
    }
    const uploadedPaths = [];
    for (const file of files) {
      const ext = file.type === 'image/jpeg' ? 'jpg' : file.type.split('/')[1];
      const path = itemId + '/' + crypto.randomUUID() + '.' + ext;
      const { error } = await supabaseClient.storage.from(STORE_BUCKET).upload(path, file, { contentType: file.type, upsert: false, cacheControl: '31536000' });
      if (error) {
        if (uploadedPaths.length) await supabaseClient.storage.from(STORE_BUCKET).remove(uploadedPaths);
        if (isNew) await supabaseClient.from('mithaq_store_items').delete().eq('id', itemId);
        status.textContent = 'تعذر رفع الصورة: ' + error.message;
        button.disabled = false;
        return;
      }
      uploadedPaths.push(path);
    }
    if (uploadedPaths.length) {
      const imageRows = uploadedPaths.map((path, index) => ({
        item_id: itemId, object_path: path,
        sort_order: storeEditingImages.length + index,
        alt_text: title
      }));
      const { error } = await supabaseClient.from('mithaq_store_images').insert(imageRows);
      if (error) {
        await supabaseClient.storage.from(STORE_BUCKET).remove(uploadedPaths);
        if (isNew) await supabaseClient.from('mithaq_store_items').delete().eq('id', itemId);
        status.textContent = 'تعذر حفظ صور المعروض: ' + error.message;
        button.disabled = false;
        return;
      }
    }
    const { error: updateError } = await supabaseClient.from('mithaq_store_items')
      .update({ ...payload, is_published: published })
      .eq('id', itemId);
    if (updateError) {
      if (uploadedPaths.length) {
        await supabaseClient.from('mithaq_store_images').delete().in('object_path', uploadedPaths);
        await supabaseClient.storage.from(STORE_BUCKET).remove(uploadedPaths);
      }
      if (isNew) await supabaseClient.from('mithaq_store_items').delete().eq('id', itemId);
      status.textContent = 'تعذر إكمال حفظ المعروض: ' + updateError.message;
      button.disabled = false;
      return;
    }
    status.textContent = published ? 'تم حفظ المعروض ونشره.' : 'تم حفظ المعروض وإخفاؤه عن الأعضاء.';
    resetStoreForm();
    button.disabled = false;
    await loadMithaqStore();
  }

  async function deleteStoreItem(item) {
    if (!confirm('هل تريد حذف المعروض رقم ' + item.item_number + ' نهائياً؟')) return;
    const paths = (item.images || []).map(image => image.object_path);
    if (paths.length) {
      const { error: storageError } = await supabaseClient.storage.from(STORE_BUCKET).remove(paths);
      if (storageError) { alert('تعذر حذف صور المعروض: ' + storageError.message); return; }
    }
    const { error } = await supabaseClient.from('mithaq_store_items').delete().eq('id', item.id);
    if (error) { alert('تعذر حذف المعروض: ' + error.message); return; }
    await loadMithaqStore();
  }

  createStorePage();
  const savedRoute = (() => { try { return sessionStorage.getItem('mithaq-last-page-v1'); } catch (_) { return null; } })();
  if (savedRoute === 'store' && document.body.classList.contains('authenticated')) {
    show('store');
    loadMithaqStore();
  }
  window.loadMithaqStore = loadMithaqStore;
})();