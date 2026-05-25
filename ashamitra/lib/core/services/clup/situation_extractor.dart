// ─────────────────────────────────────────────────────────────────────────────
// Situation Extractor — Gap 1 Fix
// Full dialect coverage: West Bengal (Rarhi, Varendra, Medinipur, Murshidabad,
// Malda, Cooch Behar, Sundarbans) + all-India (Hindi, Odia, Santali, Sadri,
// Bhojpuri, Chhattisgarhi) + transliterated variants
// ─────────────────────────────────────────────────────────────────────────────

class SituationExtraction {
  final Map<String, bool> preAnswers;
  final List<String> extractedSymptoms;

  const SituationExtraction({
    required this.preAnswers,
    required this.extractedSymptoms,
  });

  bool get hasPreAnswers => preAnswers.isNotEmpty;
}

class SituationExtractor {
  static const _moduleMap = <String, List<_SymptomRule>>{
    'newborn': [
      _SymptomRule(triggers: [
        // Standard Bengali
        'দুধ খাচ্ছে না', 'দুধ টানছে না', 'বুকের দুধ খাচ্ছে না', 'খাচ্ছে না',
        // Rarhi (Birbhum, Burdwan, Bankura)
        'দুধ খাইতেছে না', 'দুধ খায় না', 'দুধ ধরছে না', 'খাইতেছে না',
        // Medinipur / Jhargram
        'দুধ খাচ্ছে গো না', 'দুধ নিচ্ছে না গো', 'খাচ্ছে না গো',
        // Murshidabad / Malda (Varendra)
        'দুধ খায় নাই', 'দুধ খাইছে না', 'দুধ ধরে নাই',
        // Cooch Behar / North Bengal
        'দুধ খাইতে পারছে না', 'দুধ খাওয়া বন্ধ',
        // Sundarbans
        'দুধ খাইতেছে নাই', 'দুধ টানছে নাই',
        // Extra synonyms
        'চুষছে না', 'চুষতে পারছে না', 'স্তন ধরছে না', 'স্তন নিচ্ছে না',
        'মুখে নিচ্ছে না', 'বুক ছাড়ছে না', 'দুধ গিলছে না', 'খাওয়া ছেড়ে দিয়েছে',
        'chusna nahi', 'stan nahi pakad raha', 'muh mein nahi le raha',
        // Hindi / Bhojpuri
        'doodh nahi pi raha', 'doodh nahi', 'dudh nahi pita',
        'stan nahi le raha',
        // Odia
        'dudha khaucha nahi', 'dudha piuchi nahi',
        // Sadri / Santali
        'doodh nai khata', 'duku nai khela',
        // English
        'not feeding', 'not breastfeeding', 'feeding stopped', 'refuses milk',
      ], questionId: 'n1', answer: true, label: 'দুধ খাচ্ছে না'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'জ্বর', 'গা গরম', 'গা পুড়ছে', 'গা পুড়ে', 'গরম লাগছে', 'তাপ আছে',
        // Rarhi dialects
        'জ্বর আইছে', 'গা জ্বলছে', 'গা জ্বলতেছে', 'জ্বর উঠছে', 'জ্বর হইছে',
        // Medinipur
        'জ্বর হচ্ছে গো', 'গা গরম গো', 'জ্বর আছে গো',
        // Murshidabad / Malda
        'জ্বর আইছে', 'জ্বর উঠছে', 'গা গরম আছে', 'জ্বর হইয়াছে',
        // Cooch Behar
        'জ্বর উঠছে', 'গা তাতছে', 'জ্বর লাগছে',
        // Sundarbans
        'জ্বর আইছে রে', 'গা গরম রে',
        // Hindi / Bhojpuri / Chhattisgarhi
        'bukhar', 'bukhaar hai', 'jwar', 'jor', 'tap aa gaya', 'garmi hai',
        'bukhar aaye', 'bukhaar aagel',
        // Odia
        'jara', 'jwara achi', 'tapa achi',
        // Sadri / Santali
        'jor', 'jor ache', 'tap ache',
        // English
        'fever', 'high temperature', 'body hot',
      ], questionId: 'n2', answer: true, label: 'জ্বর'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'শ্বাস', 'শ্বাসকষ্ট', 'শ্বাস কষ্ট', 'শ্বাস দ্রুত', 'শ্বাস টান', 'দম',
        'শ্বাস নিতে', 'শ্বাস নিতে পারছে না',
        // Rarhi
        'শ্বাস নিতে কষ্ট হচ্ছে', 'দম নিতে পারছে না', 'শ্বাস আটকে যাচ্ছে',
        'শ্বাস নিতে পারতেছে না', 'দম আটকাইছে',
        // Medinipur
        'শ্বাস নিতে পারছে না গো', 'দম নিতে পারছে না গো',
        // Murshidabad
        'শ্বাস নিতে পারছে না', 'দম বন্ধ হইয়া যাইতেছে',
        // Hindi / Bhojpuri
        'sans nahi', 'saans nahi le pa raha', 'dam ghut raha',
        'saans ki takleef',
        'sans lene mein takleef', 'dam phool raha',
        // Odia
        'nishwas neba paruchi nahi', 'dam bandi',
        // Sadri
        'sans nai aata', 'dam nai leta',
        // English
        'breathing difficulty', 'breathing fast', 'not breathing',
        'respiratory',
      ], questionId: 'n3', answer: true, label: 'শ্বাসকষ্ট'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'নাভি লাল', 'নাভি ফুলে', 'নাভিতে পুঁজ', 'নাভি থেকে', 'নাভি',
        // Rarhi
        'নাভি পেকেছে', 'নাভিতে ঘা', 'নাভি থেকে পুঁজ পড়ছে', 'নাভি ফুলছে',
        // Medinipur
        'নাভিতে সমস্যা গো', 'নাভি লাল হয়ে গেছে গো',
        // Murshidabad
        'নাভি পাকছে', 'নাভিতে পুঁজ হইছে',
        // Hindi
        'naaf mein pus', 'naaf lal hai', 'naaf sooja hua',
        'nabhi mein infection',
        // Odia
        'nabhi lal', 'nabhi phulichi',
        // English
        'umbilicus', 'cord infection', 'navel red', 'navel swollen',
        'pus navel',
      ], questionId: 'n4', answer: true, label: 'নাভিতে সমস্যা'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'নড়ছে না', 'নিস্তেজ', 'ঢিলে', 'নেতিয়ে', 'সাড়া নেই', 'কম নড়ছে',
        'নড়াচড়া নেই', 'নেতিয়ে পড়েছে',
        // Rarhi
        'নড়তেছে না', 'ঢিলা হয়ে গেছে', 'নিস্তেজ হয়ে গেছে', 'সাড়া দিচ্ছে না',
        'নড়াচড়া করছে না', 'একদম ঢিলা',
        // Medinipur
        'নড়ছে না গো', 'ঢিলে হয়ে গেছে গো', 'সাড়া নেই গো',
        // Murshidabad
        'নড়তেছে না', 'ঢিলা হইয়া গেছে', 'সাড়া দিতেছে না',
        // Cooch Behar
        'নড়াচড়া নাই', 'ঢিলা পড়ছে',
        // Extra synonyms
        'চোখ খুলছে না', 'ঘুম থেকে উঠছে না', 'একদম চুপ', 'কাঁদছে না',
        'সাড়া দিচ্ছে না', 'চোখ বন্ধ', 'নিশ্চল', 'নিস্প্রাণের মতো',
        'aankhein nahi khul rahi', 'neend se nahi uth raha', 'bilkul chup',
        // Hindi / Bhojpuri
        'hilta nahi', 'dhila ho gaya', 'kamzor ho gaya',
        'response nahi de raha',
        'nistej', 'lethargic', 'hilna band',
        // Odia
        'nuhale nahi', 'dhila hoi gala',
        // Sadri
        'hilta nai', 'dhila ho gela',
        // English
        'lethargic', 'not moving', 'weak', 'limp', 'unresponsive',
      ], questionId: 'n5', answer: true, label: 'নিস্তেজ'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'হলুদ', 'জন্ডিস', 'নীল', 'নীলাভ', 'গা হলুদ', 'চোখ হলুদ',
        'ত্বক হলুদ', 'ঠোঁট নীল',
        // Rarhi
        'গা হলদে হয়ে গেছে', 'চোখ হলদে', 'নীল হয়ে গেছে', 'গা নীলচে',
        // Medinipur
        'গা হলুদ হয়ে গেছে গো', 'চোখ হলুদ গো',
        // Murshidabad
        'গা হলদা হইছে', 'চোখ হলদা হইছে',
        // Hindi / Bhojpuri
        'peela ho gaya', 'aankhein peeli', 'neela ho gaya', 'jaundice',
        'piliya', 'nila pad gaya',
        // Odia
        'pita hoi gala', 'chokha pita',
        // English
        'jaundice', 'yellow skin', 'cyanosis', 'blue lips', 'yellow eyes',
      ], questionId: 'n6', answer: true, label: 'ত্বকের রঙ পরিবর্তন'),
    ],
    'child': [
      _SymptomRule(triggers: [
        // Standard Bengali
        'পাঁচ দিন', '৫ দিন', 'পাঁচদিন', 'অনেকদিন জ্বর', 'দীর্ঘদিন জ্বর',
        'পাঁচ দিনের বেশি', 'এক সপ্তাহ জ্বর',
        'ছয় দিন জ্বর', '৬ দিন জ্বর', 'সাত দিন জ্বর', '৭ দিন জ্বর',
        'এক সপ্তাহ ধরে জ্বর', 'কয়েকদিন ধরে জ্বর', 'বহুদিন জ্বর',
        // Rarhi
        'পাঁচ দিন ধরে জ্বর', 'পাঁচ দিন হইছে জ্বর', 'অনেকদিন ধরে জ্বর',
        'পাঁচ দিন জ্বর আছে',
        // Medinipur
        'পাঁচ দিন ধরে জ্বর গো', 'অনেকদিন জ্বর গো',
        // Murshidabad
        'পাঁচ দিন ধরে জ্বর আছে', 'পাঁচ দিন জ্বর হইছে',
        // Hindi / Bhojpuri
        'paanch din se bukhar', '5 din se jwar', 'kaafi din se bukhar',
        'hafte bhar se bukhar', 'bahut din se tap',
        // Odia
        'pancha dina dhori jara', 'bahu dina jara',
        // English
        'five days fever', 'fever for 5 days', 'prolonged fever', 'fever week',
      ], questionId: 'c1', answer: true, label: '৫ দিনের বেশি জ্বর'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'কাশি', 'শ্বাসকষ্ট', 'শ্বাস কষ্ট', 'কাশছে', 'কাশি হচ্ছে',
        // Rarhi
        'কাশতেছে', 'কাশি উঠছে', 'শ্বাস নিতে কষ্ট হচ্ছে', 'কাশি হইছে',
        // Medinipur
        'কাশছে গো', 'শ্বাসকষ্ট হচ্ছে গো',
        // Murshidabad
        'কাশতেছে', 'কাশি হইতেছে',
        // Hindi / Bhojpuri
        'khansi', 'khaansi aa rahi', 'saans ki takleef', 'khansi ho rahi',
        'khansi aagel',
        // Odia
        'khansi', 'nishwas neba kathin',
        // Sadri
        'khansi', 'sans lene mein takleef',
        // English
        'cough', 'breathing difficulty', 'breathing problem',
      ], questionId: 'c2', answer: true, label: 'কাশি/শ্বাসকষ্ট'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'ডায়রিয়া', 'পাতলা পায়খানা', 'বমি', 'বমি হচ্ছে', 'পেট খারাপ',
        // Rarhi
        'পাতলা পায়খানা হচ্ছে', 'বমি করছে', 'পেট খারাপ হইছে', 'বমি হইছে',
        'পাতলা পায়খানা হইতেছে',
        // Medinipur
        'পাতলা পায়খানা হচ্ছে গো', 'বমি হচ্ছে গো',
        // Murshidabad
        'পাতলা পায়খানা হইছে', 'বমি হইতেছে',
        // Hindi / Bhojpuri / Chhattisgarhi
        'dast', 'daast aa raha', 'ulti', 'ulti ho rahi', 'pet kharab',
        'loose motion', 'dast aagel', 'utti ho rahi',
        // Odia
        'jhada', 'banti', 'peta kharab',
        // Sadri / Santali
        'dast', 'ulti', 'pet kharab',
        // English
        'diarrhoea', 'diarrhea', 'vomiting', 'loose stool', 'stomach upset',
      ], questionId: 'c3', answer: true, label: 'ডায়রিয়া/বমি'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'খাচ্ছে না', 'খেতে চাইছে না', 'খাওয়া বন্ধ', 'খাওয়া ছেড়ে দিয়েছে',
        // Rarhi
        'খাইতেছে না', 'খাইতে চাইছে না', 'খাওয়া বন্ধ করছে', 'খাইছে না',
        // Medinipur
        'খাচ্ছে না গো', 'খাওয়া বন্ধ গো',
        // Murshidabad
        'খাইতেছে না', 'খাওয়া বন্ধ হইছে',
        // Hindi / Bhojpuri
        'khana nahi kha raha', 'kuch nahi khata', 'khana band kar diya',
        'khana nahi khata', 'khaana chhod diya',
        // Odia
        'khia paruchi nahi', 'khiba chhadichi',
        // English
        'not eating', 'refusing food', 'stopped eating', 'no appetite',
      ], questionId: 'c4', answer: true, label: 'খাচ্ছে না'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'চোখ গর্তে', 'চোখ বসে', 'ঠোঁট শুকনো', 'পানিশূন্য', 'চোখ ভেতরে',
        'ঠোঁট শুকিয়ে গেছে',
        // Rarhi
        'চোখ গর্তে ঢুকে গেছে', 'ঠোঁট শুকাইয়া গেছে', 'চোখ বসে গেছে',
        // Medinipur
        'চোখ গর্তে গো', 'ঠোঁট শুকনো গো',
        // Murshidabad
        'চোখ বসে গেছে', 'ঠোঁট শুকাইছে',
        // Hindi / Bhojpuri
        'aankhein andar dhans gayi', 'honth sukhe hain', 'paani ki kami',
        'dehydration', 'aankhein dhans gayi',
        // Odia
        'chokha bhitare gala', 'thota shukhi gala',
        // English
        'sunken eyes', 'dry lips', 'dehydration', 'dehydrated',
      ], questionId: 'c5', answer: true, label: 'পানিশূন্যতা'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'ওজন কম', 'শুকিয়ে গেছে', 'রোগা', 'হাড় বের হয়ে গেছে', 'অপুষ্টি',
        // Rarhi
        'শুকাইয়া গেছে', 'ওজন কমে গেছে', 'হাড় বাইর হয়ে গেছে',
        // Medinipur
        'শুকিয়ে গেছে গো', 'ওজন কম গো',
        // Murshidabad
        'শুকাইছে', 'ওজন কমছে',
        // Hindi / Bhojpuri
        'wajan kam', 'sukh gaya', 'haddi nikal rahi', 'kuposhan',
        'patla ho gaya', 'wajan ghata',
        // Odia
        'wajana kama', 'shukhi gala',
        // English
        'weight loss', 'wasting', 'malnourished', 'thin', 'underweight',
      ], questionId: 'c6', answer: true, label: 'ওজন কম'),
    ],
    'pregnancy': [
      _SymptomRule(triggers: [
        // Standard Bengali
        'মাথা ব্যথা', 'মাথা ধরেছে', 'রক্তচাপ', 'বিপি', 'মাথা ব্যাথা',
        'মাথা ভারী', 'মাথা ভার লাগছে', 'বুক ধড়ফড়', 'বুক ধড়ফড় করছে',
        'ঘাড় ব্যথা', 'ঘাড়ে ব্যথা', 'চোখে ব্যথা', 'কানে শোঁ শোঁ',
        'bp বেশি', 'প্রেশার বেশি', 'প্রেশার হাই',
        // Rarhi dialects
        'মাথা ব্যথা করছে', 'মাথা ধরছে', 'মাথায় ব্যথা', 'মাথা ব্যথা হইছে',
        'মাথা ব্যথা করতেছে', 'মাথা ধরছে গো',
        // Medinipur
        'মাথা ব্যথা হচ্ছে গো', 'মাথা ধরেছে গো', 'বিপি বেশি গো',
        // Murshidabad / Malda
        'মাথা ব্যথা আছে', 'মাথা ধরছে', 'রক্তচাপ বেশি',
        // Cooch Behar
        'মাথা ব্যথা করছে', 'বিপি বেশি হইছে',
        // Sundarbans
        'মাথা ব্যথা রে', 'মাথা ধরছে রে',
        // Hindi / Bhojpuri
        'sir dard', 'sar dard', 'bp high', 'blood pressure badha hua',
        'sir mein dard', 'sar mein dard hai', 'bp badhgel',
        // Odia
        'matha byatha', 'bp besi',
        // Chhattisgarhi
        'matha dukhath', 'bp jyada',
        // English
        'headache', 'head pain', 'high bp', 'blood pressure high',
      ], questionId: 'p1', answer: true, label: 'মাথা ব্যথা/উচ্চ রক্তচাপ'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'পা ফুলেছে', 'মুখ ফুলেছে', 'ফোলা', 'পা ফুলে', 'হাত ফুলেছে',
        // Rarhi
        'পা ফুলছে', 'পা ফুলে গেছে', 'মুখ ফুলে গেছে', 'পা ফুলতেছে',
        'পা ফুলছে গো', 'হাত ফুলছে',
        // Medinipur
        'পা ফুলেছে গো', 'মুখ ফুলেছে গো', 'ফোলা হয়েছে গো',
        // Murshidabad
        'পা ফুলছে', 'মুখ ফুলছে', 'পা ফুলে গেছে',
        // Cooch Behar
        'পা ফুলছে', 'মুখ ফুলছে',
        // Hindi / Bhojpuri
        'pair sooja hua', 'munh sooja', 'sujan', 'pair mein sujan',
        'haath pair sooje', 'sujan aagel',
        // Odia
        'pada phulichi', 'mukha phulichi',
        // English
        'swelling', 'swollen legs', 'swollen face', 'oedema', 'edema',
      ], questionId: 'p2', answer: true, label: 'ফোলা'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'রক্তপাত', 'রক্ত পড়ছে', 'পেট ব্যথা', 'রক্ত যাচ্ছে', 'রক্ত পড়ছে',
        'তীব্র পেট ব্যথা',
        // Rarhi
        'রক্ত পড়তেছে', 'পেটে ব্যথা হচ্ছে', 'রক্ত পড়ছে গো', 'পেট ব্যথা করছে',
        'রক্ত যাইতেছে', 'পেটে ব্যথা হইছে',
        // Medinipur
        'রক্ত পড়ছে গো', 'পেট ব্যথা হচ্ছে গো',
        // Murshidabad
        'রক্ত পড়তেছে', 'পেটে ব্যথা আছে',
        // Hindi / Bhojpuri
        'khoon aa raha', 'pet mein dard', 'bleeding ho rahi',
        'khoon nikal raha',
        'pet dard', 'khoon aagel',
        // Odia
        'rakta paruchi', 'peta byatha',
        // Chhattisgarhi
        'khoon aavat hae', 'pet dukhath',
        // English
        'bleeding', 'blood coming', 'abdominal pain', 'stomach pain',
      ], questionId: 'p3', answer: true, label: 'রক্তপাত/পেট ব্যথা'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'বাচ্চা নড়ছে না', 'নড়াচড়া কম', 'বাচ্চা নড়ে না', 'কম নড়ছে',
        'বাচ্চার নড়াচড়া নেই',
        // Rarhi
        'বাচ্চা নড়তেছে না', 'বাচ্চা নড়াচড়া করছে না', 'বাচ্চা নড়ছে না গো',
        'পেটের বাচ্চা নড়ছে না',
        // Medinipur
        'বাচ্চা নড়ছে না গো', 'নড়াচড়া কম গো',
        // Murshidabad
        'বাচ্চা নড়তেছে না', 'বাচ্চা নড়াচড়া করছে না',
        // Hindi / Bhojpuri
        'bachcha hilta nahi', 'pet mein bachcha nahi hil raha', 'movement nahi',
        'bachcha nahi hilta', 'movement kam',
        // Odia
        'pila hiluchi nahi', 'movement kama',
        // English
        'baby not moving', 'fetal movement reduced', 'no movement',
        'less movement',
      ], questionId: 'p4', answer: true, label: 'বাচ্চার নড়াচড়া কম'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'checkup হয়নি', 'anc মিস', 'checkup বাদ', 'চেকআপ হয়নি',
        'ডাক্তার দেখানো হয়নি',
        // Rarhi
        'চেকআপ হয় নাই', 'ডাক্তার দেখানো হয় নাই', 'anc হয় নাই',
        // Medinipur
        'চেকআপ হয়নি গো', 'ডাক্তার দেখানো হয়নি গো',
        // Murshidabad
        'চেকআপ হয় নাই', 'ডাক্তার দেখানো হয় নাই',
        // Hindi
        'checkup nahi hua', 'doctor nahi dikhaya', 'anc nahi hua',
        'janch nahi hui',
        // English
        'missed anc', 'no checkup', 'not seen doctor', 'anc missed',
      ], questionId: 'p5', answer: true, label: 'ANC মিস'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'চোখে ঝাপসা', 'ঝাপসা দেখছে', 'মাথা ঘুরছে', 'চোখ ঝাপসা',
        'মাথা ঘোরা', 'চোখে অন্ধকার',
        'মাথা ঘুরে পড়ে গেছে', 'চোখে আলো সহ্য হচ্ছে না', 'চোখে ঝিলিক',
        'দেখতে পাচ্ছে না', 'চোখে সমস্যা', 'মাথা ঘুরে যাচ্ছে',
        // Rarhi
        'মাথা ঘুরাইতেছে', 'চোখে ঝাপসা লাগছে', 'মাথা ঘুরছে গো',
        'চোখে কম দেখছে', 'মাথা ঘুরতেছে',
        // Medinipur
        'মাথা ঘুরছে গো', 'চোখে ঝাপসা গো',
        // Murshidabad
        'মাথা ঘুরাইতেছে', 'চোখে ঝাপসা লাগছে',
        // Cooch Behar
        'মাথা ঘুরছে', 'চোখে ঝাপসা',
        // Hindi / Bhojpuri
        'aankhon mein dhundla', 'chakkar aa raha', 'sir ghoom raha',
        'aankhein dhundhli', 'chakkar aagel',
        // Odia
        'matha ghuruchi', 'chokha andhara',
        // Chhattisgarhi
        'matha ghoomth', 'aankhon mein andhera',
        // English
        'blurred vision', 'dizziness', 'dizzy', 'vision blurred',
        'head spinning',
      ], questionId: 'p6', answer: true, label: 'ঝাপসা দৃষ্টি/মাথা ঘোরা'),
    ],
    'delivery_pnc': [
      _SymptomRule(triggers: [
        // Standard Bengali
        'রক্তপাত', 'রক্ত পড়ছে', 'দুর্গন্ধ স্রাব', 'অনেক রক্ত', 'রক্ত যাচ্ছে',
        // Rarhi
        'রক্ত পড়তেছে', 'রক্ত যাইতেছে', 'দুর্গন্ধ স্রাব হচ্ছে',
        'অনেক রক্ত পড়ছে',
        // Medinipur
        'রক্ত পড়ছে গো', 'দুর্গন্ধ স্রাব হচ্ছে গো',
        // Murshidabad
        'রক্ত পড়তেছে', 'দুর্গন্ধ স্রাব হইতেছে',
        // Hindi / Bhojpuri
        'khoon aa raha', 'badbu wala discharge', 'bahut khoon',
        'bleeding ho rahi',
        'gandha discharge', 'khoon aagel',
        // Odia
        'rakta paruchi', 'durgandha discharge',
        // English
        'bleeding', 'foul discharge', 'excessive bleeding', 'blood coming',
      ], questionId: 'pp1', answer: true, label: 'রক্তপাত/দুর্গন্ধ স্রাব'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'জ্বর', 'ঠান্ডা লাগছে', 'কাঁপছে', 'জ্বর আছে',
        // Rarhi
        'জ্বর হইছে', 'ঠান্ডা লাগতেছে', 'কাঁপতেছে', 'জ্বর উঠছে',
        // Medinipur
        'জ্বর হচ্ছে গো', 'ঠান্ডা লাগছে গো',
        // Murshidabad
        'জ্বর হইতেছে', 'ঠান্ডা লাগতেছে',
        // Hindi / Bhojpuri
        'bukhar', 'thand lag rahi', 'kaanp rahi', 'jwar', 'bukhar aagel',
        // Odia
        'jara', 'thanda laguchi',
        // English
        'fever', 'chills', 'shivering', 'high temperature',
      ], questionId: 'pp2', answer: true, label: 'জ্বর'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'স্তন ব্যথা', 'বুকে ব্যথা', 'স্তন ফুলেছে', 'দুধ জমেছে', 'বুক ব্যথা',
        // Rarhi
        'বুকে ব্যথা করছে', 'স্তন ফুলছে', 'দুধ জমে গেছে', 'বুক ব্যথা করছে',
        // Medinipur
        'বুকে ব্যথা হচ্ছে গো', 'স্তন ফুলেছে গো',
        // Murshidabad
        'বুকে ব্যথা হইতেছে', 'স্তন ফুলছে',
        // Hindi / Bhojpuri
        'chhaati mein dard', 'stan mein dard', 'stan sooja', 'doodh jam gaya',
        'stan dard', 'chhaati dard',
        // Odia
        'chhaati byatha', 'stan phulichi',
        // English
        'breast pain', 'breast swelling', 'mastitis', 'engorged breast',
      ], questionId: 'pp3', answer: true, label: 'স্তনে ব্যথা'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'পেট ব্যথা', 'সেলাই', 'ক্ষত', 'পেটে ব্যথা', 'সেলাইয়ে সমস্যা',
        // Rarhi
        'পেটে ব্যথা হচ্ছে', 'সেলাই খুলে গেছে', 'পেট ব্যথা করছে',
        'সেলাইয়ে সমস্যা হচ্ছে',
        // Medinipur
        'পেট ব্যথা হচ্ছে গো', 'সেলাইয়ে সমস্যা গো',
        // Murshidabad
        'পেটে ব্যথা হইতেছে', 'সেলাই খুলছে',
        // Hindi / Bhojpuri
        'pet mein dard', 'tanka khul gaya', 'ghav', 'pet dard',
        'tanka mein problem',
        // Odia
        'peta byatha', 'tanka khuli gala',
        // English
        'abdominal pain', 'suture problem', 'wound', 'stitches open',
      ], questionId: 'pp4', answer: true, label: 'পেট ব্যথা/সেলাই'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'প্রস্রাবে জ্বালা', 'প্রস্রাব কষ্ট', 'প্রস্রাবে ব্যথা',
        // Rarhi
        'প্রস্রাবে জ্বালা করছে', 'প্রস্রাব করতে কষ্ট হচ্ছে',
        'প্রস্রাবে জ্বালা হইছে',
        // Medinipur
        'প্রস্রাবে জ্বালা হচ্ছে গো',
        // Murshidabad
        'প্রস্রাবে জ্বালা হইতেছে',
        // Hindi / Bhojpuri
        'peshab mein jalan', 'peshab karne mein takleef', 'mutne mein dard',
        'peshab mein dard',
        // Odia
        'prastab re jwala',
        // English
        'burning urination', 'painful urination', 'uti', 'dysuria',
      ], questionId: 'pp5', answer: true, label: 'প্রস্রাবে জ্বালা'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'দুর্বল', 'মাথা ঘুরছে', 'ফ্যাকাশে', 'অনেক দুর্বল', 'শক্তি নেই',
        'রক্তশূন্য', 'রক্তস্বল্পতা', 'হাত-পা ঠান্ডা', 'হাত পা ঠান্ডা',
        'ফ্যাকাশে ঠোঁট', 'ঠোঁট সাদা', 'নখ সাদা', 'চোখ সাদা',
        'রক্ত কম', 'অ্যানিমিয়া', 'anemia',
        // Rarhi
        'দুর্বল হয়ে গেছে', 'মাথা ঘুরাইতেছে', 'ফ্যাকাশে হয়ে গেছে',
        'দুর্বল লাগছে', 'শক্তি নাই',
        // Medinipur
        'দুর্বল হয়ে গেছে গো', 'মাথা ঘুরছে গো',
        // Murshidabad
        'দুর্বল হইয়া গেছে', 'মাথা ঘুরাইতেছে',
        // Hindi / Bhojpuri
        'kamzor', 'chakkar aa raha', 'chehra pila', 'bahut kamzor',
        'takat nahi', 'kamzor ho gaili',
        // Odia
        'durbala', 'matha ghuruchi',
        // English
        'weakness', 'dizziness', 'pallor', 'very weak', 'no energy',
      ], questionId: 'pp6', answer: true, label: 'দুর্বলতা'),
    ],
    'immunisation': [
      _SymptomRule(triggers: [
        // Standard Bengali
        'টিকা মিস', 'টিকা হয়নি', 'টিকা বাদ', 'টিকা দেওয়া হয়নি',
        'টিকা নেওয়া হয়নি', 'টিকা বাকি', 'টিকা মিস হয়েছে', 'ভ্যাকসিন মিস',
        // Rarhi / Varendra
        'টিকা মিস হইছে', 'টিকা দেয় নাই', 'টিকা দেওয়া হয় নাই',
        'টিকা বাকি আছে', 'টিকা দেই নাই',
        // Hindi / Bhojpuri
        'tika nahi laga', 'tika miss', 'tika nahi', 'tika chhut gaya',
        'vaccine miss',
        // English
        'missed vaccine', 'vaccine missed', 'immunization missed',
        'missed immunization',
      ], questionId: 'im2', answer: true, label: 'টিকা মিস'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'অসুস্থ', 'অসুখ', 'জ্বর', 'গা গরম', 'সর্দি', 'কাশি', 'এখন অসুস্থ',
        // Rarhi / Varendra
        'অসুস্থ আছে', 'অসুস্থ হইছে', 'শরীর খারাপ', 'গা গরম আছে',
        // Hindi / Bhojpuri
        'bimar', 'bimaar', 'tabiyat kharab', 'bukhar hai',
        // English
        'sick', 'unwell', 'not well', 'ill',
      ], questionId: 'im4', answer: true, label: 'এখন অসুস্থ'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'বুস্টার', 'বুস্টার মিস', 'বুস্টার ডোজ', 'বুস্টার বাকি',
        'বুস্টার হয়নি',
        // Hindi
        'booster nahi', 'booster miss',
        // English
        'booster missed', 'missed booster', 'booster dose',
      ], questionId: 'im5', answer: true, label: 'বুস্টার ডোজ মিস'),
    ],
    'emergency': [
      _SymptomRule(triggers: [
        // Standard Bengali
        'রক্ত থামছে না', 'অনেক রক্ত', 'রক্তপাত', 'রক্ত পড়ছে',
        // Rarhi
        'রক্ত থামতেছে না', 'অনেক রক্ত পড়ছে', 'রক্ত পড়তেছে',
        // Medinipur
        'রক্ত থামছে না গো', 'অনেক রক্ত পড়ছে গো',
        // Murshidabad
        'রক্ত থামতেছে না', 'রক্ত পড়তেছে',
        // Hindi / Bhojpuri
        'khoon band nahi ho raha', 'bahut khoon', 'khoon nikal raha',
        'khoon ruk nahi raha', 'khoon aagel',
        // Odia
        'rakta bandha heunahin', 'bahuta rakta',
        // English
        'bleeding not stopping', 'excessive bleeding', 'haemorrhage',
        'blood loss',
      ], questionId: 'e1', answer: true, label: 'রক্তপাত'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'খিঁচুনি', 'অজ্ঞান', 'চোখ উল্টে', 'কাঁপছে', 'ঝাঁকুনি',
        // Rarhi
        'খিঁচুনি হইছে', 'অজ্ঞান হয়ে গেছে', 'চোখ উল্টে গেছে',
        'কাঁপতেছে', 'খিচুনি দিছে',
        // Medinipur
        'খিঁচুনি হচ্ছে গো', 'অজ্ঞান হয়ে গেছে গো',
        // Murshidabad
        'খিঁচুনি হইছে', 'অজ্ঞান হইয়া গেছে',
        // Hindi / Bhojpuri
        'mirgi', 'behosh', 'aankhein palat gayi', 'kaanp raha', 'jhatkaa',
        'behosh ho gaili', 'mirgi aagel',
        // Odia
        'khichuni', 'behosh hoi gala',
        // Sadri / Santali
        'khichuni', 'behosh',
        // English
        'seizure', 'convulsion', 'unconscious', 'fits', 'eyes rolled back',
      ], questionId: 'e2', answer: true, label: 'খিঁচুনি/অজ্ঞান'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'শ্বাস বন্ধ', 'দম বন্ধ', 'শ্বাস নিতে পারছে না',
        // Rarhi
        'শ্বাস বন্ধ হয়ে গেছে', 'দম বন্ধ হয়ে গেছে', 'শ্বাস নিতে পারতেছে না',
        // Medinipur
        'শ্বাস বন্ধ হয়ে গেছে গো',
        // Murshidabad
        'শ্বাস বন্ধ হইয়া গেছে',
        // Hindi / Bhojpuri
        'sans band', 'dam ghut gaya', 'saans nahi le pa raha',
        'sans band ho gaili',
        // Odia
        'nishwas bandi',
        // English
        'not breathing', 'stopped breathing', 'respiratory arrest',
        'airway blocked',
      ], questionId: 'e3', answer: true, label: 'শ্বাস বন্ধ'),
      _SymptomRule(triggers: [
        // Standard Bengali
        'সাড়া নেই', 'জ্ঞান নেই', 'সাড়া দিচ্ছে না',
        // Rarhi
        'সাড়া দিতেছে না', 'জ্ঞান নাই', 'সাড়া নাই',
        // Medinipur
        'সাড়া নেই গো', 'জ্ঞান নেই গো',
        // Murshidabad
        'সাড়া দিতেছে না', 'জ্ঞান নাই',
        // Hindi / Bhojpuri
        'hosh nahi', 'response nahi de raha', 'behosh', 'hosh nahi hai',
        // Odia
        'hosh nahi', 'sara nahi deucha',
        // English
        'unresponsive', 'unconscious', 'no response', 'not responding',
      ], questionId: 'e4', answer: true, label: 'সাড়া নেই'),
    ],
  };

  // Negative phrases: if any matches, record answer=false for that question.
  // Checked AFTER positive so a positive match always wins.
  static const _negativeMap = <String, List<String>>{
    'n1': ['দুধ খাচ্ছে', 'দুধ টানছে', 'ভালো খাচ্ছে', 'খাচ্ছে ঠিকঠাক',
           'feeding well', 'breastfeeding well'],
    'n2': ['জ্বর নেই', 'গা গরম নেই', 'জ্বর হয়নি', 'no fever'],
    'n3': ['শ্বাস ঠিক আছে', 'শ্বাস স্বাভাবিক', 'breathing normal'],
    'n5': ['নড়ছে', 'সাড়া দিচ্ছে', 'সক্রিয়', 'active', 'moving well'],
    'p1': ['মাথা ব্যথা নেই', 'বিপি ঠিক আছে', 'bp normal', 'no headache'],
    'p2': ['ফোলা নেই', 'পা ফোলেনি', 'no swelling'],
    'p3': ['রক্তপাত নেই', 'রক্ত পড়ছে না', 'পেট ব্যথা নেই', 'no bleeding'],
    'p4': ['বাচ্চা নড়ছে', 'নড়াচড়া আছে', 'baby moving', 'movement normal'],
    'p6': ['মাথা ঘুরছে না', 'চোখ ঠিক আছে', 'no dizziness', 'vision clear'],
    'pp1': ['রক্তপাত নেই', 'রক্ত পড়ছে না', 'no bleeding'],
    'pp2': ['জ্বর নেই', 'no fever'],
    'c1': ['জ্বর নেই', 'জ্বর ছিল না', 'no fever'],
    'c3': ['বমি নেই', 'পাতলা পায়খানা নেই', 'no diarrhoea', 'no vomiting'],
    'c5': ['পানিশূন্য নয়', 'চোখ ঠিক আছে', 'not dehydrated'],
  };

  SituationExtraction extract({
    required String situation,
    required String moduleId,
  }) {
    if (situation.trim().isEmpty) {
      return const SituationExtraction(preAnswers: {}, extractedSymptoms: []);
    }

    final text = situation.toLowerCase();
    final rules = _moduleMap[moduleId] ?? [];
    final preAnswers = <String, bool>{};
    final extractedSymptoms = <String>[];

    // Positive matching
    for (final rule in rules) {
      for (final trigger in rule.triggers) {
        if (text.contains(trigger.toLowerCase())) {
          preAnswers[rule.questionId] = rule.answer;
          if (!extractedSymptoms.contains(rule.label)) {
            extractedSymptoms.add(rule.label);
          }
          break;
        }
      }
    }

    // Negative matching — only fills gaps not already set by positive match
    final negRules = _negativeMap;
    for (final entry in negRules.entries) {
      if (preAnswers.containsKey(entry.key)) continue;
      for (final phrase in entry.value) {
        if (text.contains(phrase.toLowerCase())) {
          preAnswers[entry.key] = false;
          break;
        }
      }
    }

    return SituationExtraction(
      preAnswers: preAnswers,
      extractedSymptoms: extractedSymptoms,
    );
  }
}

class _SymptomRule {
  final List<String> triggers;
  final String questionId;
  final bool answer;
  final String label;

  const _SymptomRule({
    required this.triggers,
    required this.questionId,
    required this.answer,
    required this.label,
  });
}