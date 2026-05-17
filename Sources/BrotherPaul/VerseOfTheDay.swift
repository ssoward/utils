import Foundation

struct Verse: Codable, Equatable {
    let reference: String
    let text: String
    /// Free-form attribution: "Book of Mormon", "KJV New Testament", or
    /// whatever the user adds for custom entries. Optional so old files
    /// without this field still decode.
    let source: String?

    init(reference: String, source: String? = nil, text: String) {
        self.reference = reference
        self.text = text
        self.source = source
    }
}

enum VerseOfTheDay {

    static let seedVersion = 2

    /// Today's verse. Reads `~/Library/Application Support/BrotherPaul/verses.json`
    /// if it exists, otherwise falls back to `defaultVerses` below. Selection is
    /// day-of-year modulo verse-count, so the same date each year shows the
    /// same verse.
    static func todays(now: Date = Date()) -> Verse {
        let verses = customVerses ?? defaultVerses
        guard !verses.isEmpty else { return defaultVerses[0] }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        return verses[(day - 1) % verses.count]
    }

    /// A random verse from the same pool `todays()` draws from, never equal to
    /// the one passed in. Falls back to `todays()` if the pool is a single
    /// verse.
    static func randomVerse(excluding current: Verse?) -> Verse {
        let verses = customVerses ?? defaultVerses
        guard let current = current, verses.count > 1 else {
            return verses.randomElement() ?? defaultVerses[0]
        }
        let pool = verses.filter { $0 != current }
        return pool.randomElement() ?? verses[0]
    }

    /// Path of the user-editable verse file. Created on demand by `installSeed()`.
    static var customFileURL: URL {
        ConfigManager.shared.configDirectory.appendingPathComponent("verses.json")
    }

    private static var seedMarkerURL: URL {
        ConfigManager.shared.configDirectory.appendingPathComponent(".verses-seed-version")
    }

    /// Write the default list to disk so the user has something to edit.
    /// Reseeds whenever the seedVersion changes — so when we expand the
    /// default list, existing installations pick it up without manual steps.
    /// To preserve hand-edits, the user can change the seedVersion marker
    /// (or simply re-edit after the refresh).
    static func installSeed() {
        let url = customFileURL
        let marker = seedMarkerURL
        let fm = FileManager.default

        let currentVersion: Int? = {
            guard let data = try? Data(contentsOf: marker),
                  let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }
            return Int(s)
        }()

        // If the file exists AND the marker matches the current seedVersion,
        // assume user has their preferred set; don't touch.
        if fm.fileExists(atPath: url.path), currentVersion == seedVersion {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(defaultVerses) else { return }
        try? data.write(to: url, options: .atomic)
        try? "\(seedVersion)".write(to: marker, atomically: true, encoding: .utf8)
        cachedCustomVerses = .uninitialized
    }

    private enum CachedLoad {
        case uninitialized
        case loaded([Verse]?)
    }
    private static var cachedCustomVerses: CachedLoad = .uninitialized

    private static var customVerses: [Verse]? {
        if case .loaded(let v) = cachedCustomVerses { return v }
        let url = customFileURL
        let loaded: [Verse]? = {
            guard let data = try? Data(contentsOf: url),
                  let verses = try? JSONDecoder().decode([Verse].self, from: data),
                  !verses.isEmpty
            else { return nil }
            return verses
        }()
        cachedCustomVerses = .loaded(loaded)
        return loaded
    }

    // MARK: - Default verse list

    private static let bom = "Book of Mormon"
    private static let kjv = "KJV New Testament"

    /// Christ-focused public-domain passages: 60 from the Book of Mormon and
    /// 60 from the four Gospels of the KJV New Testament. If wording or
    /// references look off, edit `verses.json` via menu → Edit Daily Verses…
    static let defaultVerses: [Verse] = [

        // ────────────────────────────────────────────────────────────────
        // BOOK OF MORMON (60)
        // ────────────────────────────────────────────────────────────────

        Verse(reference: "1 Nephi 10:6", source: bom, text:
            "Wherefore, all mankind were in a lost and in a fallen state, and ever would be save they should rely on this Redeemer."),
        Verse(reference: "1 Nephi 11:22", source: bom, text:
            "And I answered him, saying: It is the love of God, which sheddeth itself abroad in the hearts of the children of men; wherefore, it is the most desirable above all things."),
        Verse(reference: "1 Nephi 19:9", source: bom, text:
            "And the world, because of their iniquity, shall judge him to be a thing of naught; wherefore they scourge him, and he suffereth it; and they smite him, and he suffereth it. Yea, they spit upon him, and he suffereth it, because of his loving kindness and his long-suffering towards the children of men."),
        Verse(reference: "2 Nephi 2:8", source: bom, text:
            "Wherefore, how great the importance to make these things known unto the inhabitants of the earth, that they may know that there is no flesh that can dwell in the presence of God, save it be through the merits, and mercy, and grace of the Holy Messiah, who layeth down his life according to the flesh, and taketh it again by the power of the Spirit, that he may bring to pass the resurrection of the dead, being the first that should rise."),
        Verse(reference: "2 Nephi 9:21", source: bom, text:
            "And he cometh into the world that he may save all men if they will hearken unto his voice; for behold, he suffereth the pains of all men, yea, the pains of every living creature, both men, women, and children, who belong to the family of Adam."),
        Verse(reference: "2 Nephi 9:41", source: bom, text:
            "Behold, the way for man is narrow, but it lieth in a straight course before him, and the keeper of the gate is the Holy One of Israel; and he employeth no servant there; and there is none other way save it be by the gate; for he cannot be deceived, for the Lord God is his name."),
        Verse(reference: "2 Nephi 25:23", source: bom, text:
            "For we labor diligently to write, to persuade our children, and also our brethren, to believe in Christ, and to be reconciled to God; for we know that it is by grace that we are saved, after all we can do."),
        Verse(reference: "2 Nephi 25:26", source: bom, text:
            "And we talk of Christ, we rejoice in Christ, we preach of Christ, we prophesy of Christ, and we write according to our prophecies, that our children may know to what source they may look for a remission of their sins."),
        Verse(reference: "2 Nephi 26:24", source: bom, text:
            "He doeth not anything save it be for the benefit of the world; for he loveth the world, even that he layeth down his own life that he may draw all men unto him."),
        Verse(reference: "2 Nephi 26:33", source: bom, text:
            "…he inviteth them all to come unto him and partake of his goodness; and he denieth none that come unto him, black and white, bond and free, male and female; and he remembereth the heathen; and all are alike unto God, both Jew and Gentile."),
        Verse(reference: "2 Nephi 31:13", source: bom, text:
            "Wherefore, my beloved brethren, I know that if ye shall follow the Son, with full purpose of heart, acting no hypocrisy and no deception before God, but with real intent, repenting of your sins, witnessing unto the Father that ye are willing to take upon you the name of Christ, by baptism…"),
        Verse(reference: "2 Nephi 31:20", source: bom, text:
            "Wherefore, ye must press forward with a steadfastness in Christ, having a perfect brightness of hope, and a love of God and of all men. Wherefore, if ye shall press forward, feasting upon the word of Christ, and endure to the end, behold, thus saith the Father: Ye shall have eternal life."),
        Verse(reference: "Jacob 4:11", source: bom, text:
            "Wherefore, beloved brethren, be reconciled unto him through the atonement of Christ, his Only Begotten Son, and ye may obtain a resurrection, according to the power of the resurrection which is in Christ, and be presented as the first-fruits of Christ unto God…"),
        Verse(reference: "Enos 1:5", source: bom, text:
            "And there came a voice unto me, saying: Enos, thy sins are forgiven thee, and thou shalt be blessed."),
        Verse(reference: "Mosiah 2:21", source: bom, text:
            "I say unto you that if ye should serve him who has created you from the beginning, and is preserving you from day to day, by lending you breath, that ye may live and move and do according to your own will, and even supporting you from one moment to another—I say, if ye should serve him with all your whole souls yet ye would be unprofitable servants."),
        Verse(reference: "Mosiah 3:17", source: bom, text:
            "And moreover, I say unto you, that there shall be no other name given nor any other way nor means whereby salvation can come unto the children of men, only in and through the name of Christ, the Lord Omnipotent."),
        Verse(reference: "Mosiah 3:19", source: bom, text:
            "For the natural man is an enemy to God, and has been from the fall of Adam, and will be, forever and ever, unless he yields to the enticings of the Holy Spirit, and putteth off the natural man and becometh a saint through the atonement of Christ the Lord, and becometh as a child, submissive, meek, humble, patient, full of love, willing to submit to all things which the Lord seeth fit to inflict upon him, even as a child doth submit to his father."),
        Verse(reference: "Mosiah 5:8", source: bom, text:
            "And under this head ye are made free, and there is no other head whereby ye can be made free. There is no other name given whereby salvation cometh; therefore, I would that ye should take upon you the name of Christ…"),
        Verse(reference: "Mosiah 15:1", source: bom, text:
            "And now Abinadi said unto them: I would that ye should understand that God himself shall come down among the children of men, and shall redeem his people."),
        Verse(reference: "Mosiah 16:8", source: bom, text:
            "But there is a resurrection, therefore the grave hath no victory, and the sting of death is swallowed up in Christ."),
        Verse(reference: "Mosiah 16:9", source: bom, text:
            "He is the light and the life of the world; yea, a light that is endless, that can never be darkened; yea, and also a life which is endless, that there can be no more death."),
        Verse(reference: "Mosiah 26:30", source: bom, text:
            "Yea, and as often as my people repent will I forgive them their trespasses against me."),
        Verse(reference: "Alma 5:14", source: bom, text:
            "And now behold, I ask of you, my brethren of the church, have ye spiritually been born of God? Have ye received his image in your countenances? Have ye experienced this mighty change in your hearts?"),
        Verse(reference: "Alma 7:11", source: bom, text:
            "And he shall go forth, suffering pains and afflictions and temptations of every kind; and this that the word might be fulfilled which saith he will take upon him the pains and the sicknesses of his people."),
        Verse(reference: "Alma 7:12", source: bom, text:
            "And he will take upon him death, that he may loose the bands of death which bind his people; and he will take upon him their infirmities, that his bowels may be filled with mercy, according to the flesh, that he may know according to the flesh how to succor his people according to their infirmities."),
        Verse(reference: "Alma 7:13", source: bom, text:
            "Now the Spirit knoweth all things; nevertheless the Son of God suffereth according to the flesh that he might take upon him the sins of his people, that he might blot out their transgressions according to the power of his deliverance…"),
        Verse(reference: "Alma 7:14", source: bom, text:
            "Now I say unto you that ye must repent, and be born again; for the Spirit saith if ye are not born again ye cannot inherit the kingdom of heaven; therefore come and be baptized unto repentance, that ye may be washed from your sins…"),
        Verse(reference: "Alma 32:21", source: bom, text:
            "And now as I said concerning faith—faith is not to have a perfect knowledge of things; therefore if ye have faith ye hope for things which are not seen, which are true."),
        Verse(reference: "Alma 34:9", source: bom, text:
            "For it is expedient that an atonement should be made; for according to the great plan of the Eternal God there must be an atonement made, or else all mankind must unavoidably perish; yea, all are hardened; yea, all are fallen and are lost, and must perish except it be through the atonement which it is expedient should be made."),
        Verse(reference: "Alma 34:10", source: bom, text:
            "For it is expedient that there should be a great and last sacrifice; yea, not a sacrifice of man, neither of beast, neither of any manner of fowl; for it shall not be a human sacrifice; but it must be an infinite and eternal sacrifice."),
        Verse(reference: "Alma 34:14", source: bom, text:
            "And behold, this is the whole meaning of the law, every whit pointing to that great and last sacrifice; and that great and last sacrifice will be the Son of God, yea, infinite and eternal."),
        Verse(reference: "Alma 36:18", source: bom, text:
            "Now, as my mind caught hold upon this thought, I cried within my heart: O Jesus, thou Son of God, have mercy on me, who am in the gall of bitterness, and am encircled about by the everlasting chains of death."),
        Verse(reference: "Alma 38:9", source: bom, text:
            "And now, my son, I have told you this that ye may learn wisdom, that ye may learn of me that there is no other way or means whereby man can be saved, only in and through Christ. Behold, he is the life and the light of the world. Behold, he is the word of truth and righteousness."),
        Verse(reference: "Helaman 3:35", source: bom, text:
            "Nevertheless they did fast and pray oft, and did wax stronger and stronger in their humility, and firmer and firmer in the faith of Christ, unto the filling their souls with joy and consolation, yea, even to the purifying and the sanctification of their hearts, which sanctification cometh because of their yielding their hearts unto God."),
        Verse(reference: "Helaman 5:12", source: bom, text:
            "And now, my sons, remember, remember that it is upon the rock of our Redeemer, who is Christ, the Son of God, that ye must build your foundation; that when the devil shall send forth his mighty winds, yea, his shafts in the whirlwind, yea, when all his hail and his mighty storm shall beat upon you, it shall have no power over you to drag you down to the gulf of misery and endless wo, because of the rock upon which ye are built, which is a sure foundation, a foundation whereon if men build they cannot fall."),
        Verse(reference: "Helaman 14:12", source: bom, text:
            "And also that ye might know of the coming of Jesus Christ, the Son of God, the Father of heaven and of earth, the Creator of all things from the beginning; and that ye might know of the signs of his coming, to the intent that ye might believe on his name."),
        Verse(reference: "3 Nephi 5:13", source: bom, text:
            "Behold, I am a disciple of Jesus Christ, the Son of God. I have been called of him to declare his word among his people, that they might have everlasting life."),
        Verse(reference: "3 Nephi 9:14", source: bom, text:
            "Yea, verily I say unto you, if ye will come unto me ye shall have eternal life. Behold, mine arm of mercy is extended towards you, and whosoever will come, him will I receive; and blessed are those who come unto me."),
        Verse(reference: "3 Nephi 9:17", source: bom, text:
            "And as many as have received me, to them have I given to become the sons of God; and even so will I to as many as shall believe on my name, for behold, by me redemption cometh, and in me is the law of Moses fulfilled."),
        Verse(reference: "3 Nephi 9:18", source: bom, text:
            "I am the light and the life of the world. I am Alpha and Omega, the beginning and the end."),
        Verse(reference: "3 Nephi 11:10–11", source: bom, text:
            "Behold, I am Jesus Christ, whom the prophets testified shall come into the world. And behold, I am the light and the life of the world; and I have drunk out of that bitter cup which the Father hath given me, and have glorified the Father in taking upon me the sins of the world, in the which I have suffered the will of the Father in all things from the beginning."),
        Verse(reference: "3 Nephi 11:33", source: bom, text:
            "And whoso believeth in me, and is baptized, the same shall be saved; and they are they who shall inherit the kingdom of God."),
        Verse(reference: "3 Nephi 12:48", source: bom, text:
            "Therefore I would that ye should be perfect even as I, or your Father who is in heaven is perfect."),
        Verse(reference: "3 Nephi 14:7", source: bom, text:
            "Ask, and it shall be given unto you; seek, and ye shall find; knock, and it shall be opened unto you."),
        Verse(reference: "3 Nephi 17:6", source: bom, text:
            "And he said unto them: Behold, my bowels are filled with compassion towards you."),
        Verse(reference: "3 Nephi 17:7", source: bom, text:
            "Have ye any that are sick among you? Bring them hither. Have ye any that are lame, or blind, or halt, or maimed, or leprous, or that are withered, or that are deaf, or that are afflicted in any manner? Bring them hither and I will heal them, for I have compassion upon you; my bowels are filled with mercy."),
        Verse(reference: "3 Nephi 17:21", source: bom, text:
            "And it came to pass that when Jesus had spoken these words, he wept, and the multitude bare record of it, and he took their little children, one by one, and blessed them, and prayed unto the Father for them."),
        Verse(reference: "3 Nephi 18:16", source: bom, text:
            "And behold, I am the light; I have set an example for you."),
        Verse(reference: "3 Nephi 27:13–14", source: bom, text:
            "Behold I have given unto you my gospel, and this is the gospel which I have given unto you—that I came into the world to do the will of my Father, because my Father sent me. And my Father sent me that I might be lifted up upon the cross; and that I might draw all men unto me…"),
        Verse(reference: "3 Nephi 27:27", source: bom, text:
            "And know ye that ye shall be judges of this people, according to the judgment which I shall give unto you, which shall be just. Therefore, what manner of men ought ye to be? Verily I say unto you, even as I am."),
        Verse(reference: "Mormon 9:9", source: bom, text:
            "For do we not read that God is the same yesterday, today, and forever, and in him there is no variableness neither shadow of changing?"),
        Verse(reference: "Ether 3:14", source: bom, text:
            "Behold, I am he who was prepared from the foundation of the world to redeem my people. Behold, I am Jesus Christ. I am the Father and the Son."),
        Verse(reference: "Ether 12:4", source: bom, text:
            "Wherefore, whoso believeth in God might with surety hope for a better world, yea, even a place at the right hand of God, which hope cometh of faith, maketh an anchor to the souls of men, which would make them sure and steadfast, always abounding in good works, being led to glorify God."),
        Verse(reference: "Ether 12:6", source: bom, text:
            "And now, I, Moroni, would speak somewhat concerning these things; I would show unto the world that faith is things which are hoped for and not seen; wherefore, dispute not because ye see not, for ye receive no witness until after the trial of your faith."),
        Verse(reference: "Ether 12:27", source: bom, text:
            "And if men come unto me I will show unto them their weakness. I give unto men weakness that they may be humble; and my grace is sufficient for all men that humble themselves before me; for if they humble themselves before me, and have faith in me, then will I make weak things become strong unto them."),
        Verse(reference: "Moroni 7:33", source: bom, text:
            "And Christ hath said: If ye will have faith in me ye shall have power to do whatsoever thing is expedient in me."),
        Verse(reference: "Moroni 7:41", source: bom, text:
            "And what is it that ye shall hope for? Behold I say unto you that ye shall have hope through the atonement of Christ and the power of his resurrection, to be raised unto life eternal, and this because of your faith in him according to the promise."),
        Verse(reference: "Moroni 7:47", source: bom, text:
            "But charity is the pure love of Christ, and it endureth forever; and whoso is found possessed of it at the last day, it shall be well with him."),
        Verse(reference: "Moroni 7:48", source: bom, text:
            "Wherefore, my beloved brethren, pray unto the Father with all the energy of heart, that ye may be filled with this love, which he hath bestowed upon all who are true followers of his Son, Jesus Christ; that ye may become the sons of God; that when he shall appear we shall be like him, for we shall see him as he is; that we may have this hope; that we may be purified even as he is pure."),
        Verse(reference: "Moroni 8:16", source: bom, text:
            "Behold, I speak with boldness, having authority from God; and I fear not what man can do; for perfect love casteth out all fear."),
        Verse(reference: "Moroni 10:32", source: bom, text:
            "Yea, come unto Christ, and be perfected in him, and deny yourselves of all ungodliness; and if ye shall deny yourselves of all ungodliness, and love God with all your might, mind and strength, then is his grace sufficient for you, that by his grace ye may be perfect in Christ."),

        // ────────────────────────────────────────────────────────────────
        // KJV NEW TESTAMENT — Gospels (60)
        // ────────────────────────────────────────────────────────────────

        // Matthew
        Verse(reference: "Matthew 1:21", source: kjv, text:
            "And she shall bring forth a son, and thou shalt call his name JESUS: for he shall save his people from their sins."),
        Verse(reference: "Matthew 4:4", source: kjv, text:
            "But he answered and said, It is written, Man shall not live by bread alone, but by every word that proceedeth out of the mouth of God."),
        Verse(reference: "Matthew 4:19", source: kjv, text:
            "And he saith unto them, Follow me, and I will make you fishers of men."),
        Verse(reference: "Matthew 5:8", source: kjv, text:
            "Blessed are the pure in heart: for they shall see God."),
        Verse(reference: "Matthew 5:14, 16", source: kjv, text:
            "Ye are the light of the world. A city that is set on an hill cannot be hid… Let your light so shine before men, that they may see your good works, and glorify your Father which is in heaven."),
        Verse(reference: "Matthew 5:44", source: kjv, text:
            "But I say unto you, Love your enemies, bless them that curse you, do good to them that hate you, and pray for them which despitefully use you, and persecute you."),
        Verse(reference: "Matthew 6:14", source: kjv, text:
            "For if ye forgive men their trespasses, your heavenly Father will also forgive you."),
        Verse(reference: "Matthew 6:33", source: kjv, text:
            "But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you."),
        Verse(reference: "Matthew 7:7–8", source: kjv, text:
            "Ask, and it shall be given you; seek, and ye shall find; knock, and it shall be opened unto you: For every one that asketh receiveth; and he that seeketh findeth; and to him that knocketh it shall be opened."),
        Verse(reference: "Matthew 7:24", source: kjv, text:
            "Therefore whosoever heareth these sayings of mine, and doeth them, I will liken him unto a wise man, which built his house upon a rock."),
        Verse(reference: "Matthew 11:28–30", source: kjv, text:
            "Come unto me, all ye that labour and are heavy laden, and I will give you rest. Take my yoke upon you, and learn of me; for I am meek and lowly in heart: and ye shall find rest unto your souls. For my yoke is easy, and my burden is light."),
        Verse(reference: "Matthew 16:24", source: kjv, text:
            "Then said Jesus unto his disciples, If any man will come after me, let him deny himself, and take up his cross, and follow me."),
        Verse(reference: "Matthew 17:20", source: kjv, text:
            "And Jesus said unto them, Because of your unbelief: for verily I say unto you, If ye have faith as a grain of mustard seed, ye shall say unto this mountain, Remove hence to yonder place; and it shall remove; and nothing shall be impossible unto you."),
        Verse(reference: "Matthew 18:3", source: kjv, text:
            "And said, Verily I say unto you, Except ye be converted, and become as little children, ye shall not enter into the kingdom of heaven."),
        Verse(reference: "Matthew 18:20", source: kjv, text:
            "For where two or three are gathered together in my name, there am I in the midst of them."),
        Verse(reference: "Matthew 19:14", source: kjv, text:
            "But Jesus said, Suffer little children, and forbid them not, to come unto me: for of such is the kingdom of heaven."),
        Verse(reference: "Matthew 22:37–39", source: kjv, text:
            "Jesus said unto him, Thou shalt love the Lord thy God with all thy heart, and with all thy soul, and with all thy mind. This is the first and great commandment. And the second is like unto it, Thou shalt love thy neighbour as thyself."),
        Verse(reference: "Matthew 25:40", source: kjv, text:
            "And the King shall answer and say unto them, Verily I say unto you, Inasmuch as ye have done it unto one of the least of these my brethren, ye have done it unto me."),
        Verse(reference: "Matthew 26:39", source: kjv, text:
            "And he went a little further, and fell on his face, and prayed, saying, O my Father, if it be possible, let this cup pass from me: nevertheless not as I will, but as thou wilt."),
        Verse(reference: "Matthew 28:6", source: kjv, text:
            "He is not here: for he is risen, as he said. Come, see the place where the Lord lay."),
        Verse(reference: "Matthew 28:19–20", source: kjv, text:
            "Go ye therefore, and teach all nations, baptizing them in the name of the Father, and of the Son, and of the Holy Ghost: Teaching them to observe all things whatsoever I have commanded you: and, lo, I am with you alway, even unto the end of the world. Amen."),

        // Mark
        Verse(reference: "Mark 1:15", source: kjv, text:
            "And saying, The time is fulfilled, and the kingdom of God is at hand: repent ye, and believe the gospel."),
        Verse(reference: "Mark 2:17", source: kjv, text:
            "When Jesus heard it, he saith unto them, They that are whole have no need of the physician, but they that are sick: I came not to call the righteous, but sinners to repentance."),
        Verse(reference: "Mark 5:36", source: kjv, text:
            "As soon as Jesus heard the word that was spoken, he saith unto the ruler of the synagogue, Be not afraid, only believe."),
        Verse(reference: "Mark 8:34", source: kjv, text:
            "Whosoever will come after me, let him deny himself, and take up his cross, and follow me."),
        Verse(reference: "Mark 9:23", source: kjv, text:
            "Jesus said unto him, If thou canst believe, all things are possible to him that believeth."),
        Verse(reference: "Mark 9:35", source: kjv, text:
            "And he sat down, and called the twelve, and saith unto them, If any man desire to be first, the same shall be last of all, and servant of all."),
        Verse(reference: "Mark 10:14", source: kjv, text:
            "But when Jesus saw it, he was much displeased, and said unto them, Suffer the little children to come unto me, and forbid them not: for of such is the kingdom of God."),
        Verse(reference: "Mark 10:27", source: kjv, text:
            "And Jesus looking upon them saith, With men it is impossible, but not with God: for with God all things are possible."),
        Verse(reference: "Mark 10:45", source: kjv, text:
            "For even the Son of man came not to be ministered unto, but to minister, and to give his life a ransom for many."),
        Verse(reference: "Mark 11:24", source: kjv, text:
            "Therefore I say unto you, What things soever ye desire, when ye pray, believe that ye receive them, and ye shall have them."),
        Verse(reference: "Mark 12:30–31", source: kjv, text:
            "And thou shalt love the Lord thy God with all thy heart, and with all thy soul, and with all thy mind, and with all thy strength: this is the first commandment. And the second is like, namely this, Thou shalt love thy neighbour as thyself. There is none other commandment greater than these."),
        Verse(reference: "Mark 16:6", source: kjv, text:
            "And he saith unto them, Be not affrighted: Ye seek Jesus of Nazareth, which was crucified: he is risen; he is not here: behold the place where they laid him."),
        Verse(reference: "Mark 16:15", source: kjv, text:
            "And he said unto them, Go ye into all the world, and preach the gospel to every creature."),

        // Luke
        Verse(reference: "Luke 2:10–11", source: kjv, text:
            "And the angel said unto them, Fear not: for, behold, I bring you good tidings of great joy, which shall be to all people. For unto you is born this day in the city of David a Saviour, which is Christ the Lord."),
        Verse(reference: "Luke 2:14", source: kjv, text:
            "Glory to God in the highest, and on earth peace, good will toward men."),
        Verse(reference: "Luke 4:18", source: kjv, text:
            "The Spirit of the Lord is upon me, because he hath anointed me to preach the gospel to the poor; he hath sent me to heal the brokenhearted, to preach deliverance to the captives, and recovering of sight to the blind, to set at liberty them that are bruised."),
        Verse(reference: "Luke 6:31", source: kjv, text:
            "And as ye would that men should do to you, do ye also to them likewise."),
        Verse(reference: "Luke 6:38", source: kjv, text:
            "Give, and it shall be given unto you; good measure, pressed down, and shaken together, and running over, shall men give into your bosom. For with the same measure that ye mete withal it shall be measured to you again."),
        Verse(reference: "Luke 9:23", source: kjv, text:
            "And he said to them all, If any man will come after me, let him deny himself, and take up his cross daily, and follow me."),
        Verse(reference: "Luke 11:9", source: kjv, text:
            "And I say unto you, Ask, and it shall be given you; seek, and ye shall find; knock, and it shall be opened unto you."),
        Verse(reference: "Luke 12:32", source: kjv, text:
            "Fear not, little flock; for it is your Father's good pleasure to give you the kingdom."),
        Verse(reference: "Luke 15:7", source: kjv, text:
            "I say unto you, that likewise joy shall be in heaven over one sinner that repenteth, more than over ninety and nine just persons, which need no repentance."),
        Verse(reference: "Luke 18:27", source: kjv, text:
            "And he said, The things which are impossible with men are possible with God."),
        Verse(reference: "Luke 18:42", source: kjv, text:
            "And Jesus said unto him, Receive thy sight: thy faith hath saved thee."),
        Verse(reference: "Luke 19:10", source: kjv, text:
            "For the Son of man is come to seek and to save that which was lost."),
        Verse(reference: "Luke 22:42", source: kjv, text:
            "Saying, Father, if thou be willing, remove this cup from me: nevertheless not my will, but thine, be done."),
        Verse(reference: "Luke 23:34", source: kjv, text:
            "Then said Jesus, Father, forgive them; for they know not what they do."),
        Verse(reference: "Luke 23:43", source: kjv, text:
            "And Jesus said unto him, Verily I say unto thee, To day shalt thou be with me in paradise."),
        Verse(reference: "Luke 24:6", source: kjv, text:
            "He is not here, but is risen: remember how he spake unto you when he was yet in Galilee."),

        // John
        Verse(reference: "John 1:1", source: kjv, text:
            "In the beginning was the Word, and the Word was with God, and the Word was God."),
        Verse(reference: "John 1:14", source: kjv, text:
            "And the Word was made flesh, and dwelt among us, (and we beheld his glory, the glory as of the only begotten of the Father,) full of grace and truth."),
        Verse(reference: "John 1:29", source: kjv, text:
            "The next day John seeth Jesus coming unto him, and saith, Behold the Lamb of God, which taketh away the sin of the world."),
        Verse(reference: "John 3:16", source: kjv, text:
            "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
        Verse(reference: "John 4:14", source: kjv, text:
            "But whosoever drinketh of the water that I shall give him shall never thirst; but the water that I shall give him shall be in him a well of water springing up into everlasting life."),
        Verse(reference: "John 6:35", source: kjv, text:
            "And Jesus said unto them, I am the bread of life: he that cometh to me shall never hunger; and he that believeth on me shall never thirst."),
        Verse(reference: "John 7:37", source: kjv, text:
            "In the last day, that great day of the feast, Jesus stood and cried, saying, If any man thirst, let him come unto me, and drink."),
        Verse(reference: "John 8:12", source: kjv, text:
            "Then spake Jesus again unto them, saying, I am the light of the world: he that followeth me shall not walk in darkness, but shall have the light of life."),
        Verse(reference: "John 10:11", source: kjv, text:
            "I am the good shepherd: the good shepherd giveth his life for the sheep."),
        Verse(reference: "John 10:27–28", source: kjv, text:
            "My sheep hear my voice, and I know them, and they follow me: And I give unto them eternal life; and they shall never perish, neither shall any man pluck them out of my hand."),
        Verse(reference: "John 11:25–26", source: kjv, text:
            "Jesus said unto her, I am the resurrection, and the life: he that believeth in me, though he were dead, yet shall he live: And whosoever liveth and believeth in me shall never die."),
        Verse(reference: "John 13:34–35", source: kjv, text:
            "A new commandment I give unto you, That ye love one another; as I have loved you, that ye also love one another. By this shall all men know that ye are my disciples, if ye have love one to another."),
        Verse(reference: "John 14:1–3", source: kjv, text:
            "Let not your heart be troubled: ye believe in God, believe also in me. In my Father's house are many mansions: if it were not so, I would have told you. I go to prepare a place for you. And if I go and prepare a place for you, I will come again, and receive you unto myself; that where I am, there ye may be also."),
        Verse(reference: "John 14:6", source: kjv, text:
            "Jesus saith unto him, I am the way, the truth, and the life: no man cometh unto the Father, but by me."),
        Verse(reference: "John 14:15", source: kjv, text:
            "If ye love me, keep my commandments."),
        Verse(reference: "John 14:27", source: kjv, text:
            "Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be afraid."),
        Verse(reference: "John 15:5", source: kjv, text:
            "I am the vine, ye are the branches: He that abideth in me, and I in him, the same bringeth forth much fruit: for without me ye can do nothing."),
        Verse(reference: "John 15:13", source: kjv, text:
            "Greater love hath no man than this, that a man lay down his life for his friends."),
        Verse(reference: "John 16:33", source: kjv, text:
            "These things I have spoken unto you, that in me ye might have peace. In the world ye shall have tribulation: but be of good cheer; I have overcome the world."),
        Verse(reference: "John 17:3", source: kjv, text:
            "And this is life eternal, that they might know thee the only true God, and Jesus Christ, whom thou hast sent."),
        Verse(reference: "John 20:29", source: kjv, text:
            "Jesus saith unto him, Thomas, because thou hast seen me, thou hast believed: blessed are they that have not seen, and yet have believed."),
    ]
}
