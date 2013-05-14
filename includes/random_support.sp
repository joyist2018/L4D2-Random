#pragma semicolon 1
#include <sourcemod>

SUPPORT_RoundPreparation()
{
    // called before randomization
    g_bIsFirstAttack = true;
    g_bPlayersLeftStart = false;
    g_bFirstReportDone = false;
    g_iSpectateGhostCount = 0;
    
    g_bFirstTankSpawned = false;
    g_bIsTankInPlay = false;
    g_iTankClient = 0;
    
    g_iBonusCount = 0;
    
    g_bInsightSurvDone = false;     // so we only get the insight effect from a gift once per roundhalf
    g_bInsightInfDone = false;
    
    g_bNoWeaponsNoAmmo = false;
    
    // basic cleanup
    SUPPORT_CleanArrays();
    
    // handle the randomization 
    RANDOM_DetermineRandomStuff();
    
    // handle report / survivor check for second round
    if (g_bSecondHalf) {
        // doing this immediately now
        //CreateTimer(DELAY_SECONDHALF, Timer_RoundStart, _, TIMER_FLAG_NO_MAPCHANGE);
        
        g_hTimerReport = CreateTimer(DELAY_SECONDHALF_REP, Timer_RoundStartReport, _, TIMER_FLAG_NO_MAPCHANGE);
        g_bTimerReport = true;
        
        // for second half, also do a run-through to hand out gifts to all survivors
        //      because playerteam is not reliably fired for everyone
        CheckSurvivorSetup();
    }
    
    
    // do post-randomization prep
    RNDBNS_SetExtra(0);                 // clear extra round bonus
    
    // penalty bonus (only enable when required)
    if (g_bUsingPBonus) {
        SetConVarInt(FindConVar("sm_pbonus_enable"), 1);
        PBONUS_ResetRoundBonus();
    } else {
        SetConVarInt(FindConVar("sm_pbonus_enable"), 0);
    }
    
    ClearArray(g_hBlockedEntities);     // clear blind infected entities
    ClearBoomerTracking();              // clear arrays for tracking boomer combo's
    ResetGnomes();                      // clear gnome tracking array for bonus scoring
    EVENT_RoundStartPreparation();      // prepare survivors for special event
    
    SUPPORT_MultiWitchRoundPrep();      // prepare multi-witch for round, if any
    SUPPORT_MultiTankRoundPrep();       // prepare multi-/mini-tanks for round, if any
    
    
    // fix sound hook
    if (_:g_iSpecialEvent == EVT_SILENCE) {
        if (!g_bSoundHooked) {
            AddNormalSoundHook(Event_SoundPlayed);
            g_bSoundHooked = true;
        }
    } else {
        if (g_bSoundHooked) {
            RemoveNormalSoundHook(Event_SoundPlayed);
            g_bSoundHooked = false;
        }
    }
    
    // some things need to be delayed to work right
    g_hTimerReport = CreateTimer(DELAY_ROUNDPREP, Timer_DelayedRoundPrep, _, TIMER_FLAG_NO_MAPCHANGE);
    
}

public Action: Timer_DelayedRoundPrep(Handle:timer)
{
    // item replacement and blinding
    g_iCreatedEntities = 0;
    
    if (!g_bSecondHalf || !(GetConVarInt(g_hCvarEqual) & EQ_ITEMS)) {
        RandomizeItems();
    } else {
        RestoreItems();
    }
    
    // blind infected to items generated
    ItemsBlindInfected();
}

SUPPORT_CleanArrays()
{
    // clean some arrays with rounddata
    for (new i=1; i <= MaxClients; i++)
    {
        g_bArJustBeenGiven[i] = false;
        g_bArBlockPickupCall[i] = false;
    }
    
    // arrays for ZC / class changing code
    InitSpawnArrays();
}


// Event functions / difficulty
// ----------------------------

EVENT_ResetOtherCvars()
{
    // for defib event
    SetConVarInt(FindConVar("vs_defib_penalty"), g_iDefDefibPenalty);
    SetConVarInt(FindConVar("defibrillator_use_duration"), g_iDefDefibDuration);
    SetConVarFloat(FindConVar("pain_pills_decay_rate"), g_fDefPillDecayRate);
    
    SetConVarInt(FindConVar("z_spitter_limit"), g_iDefSpitterLimit);
    SetConVarInt(FindConVar("z_jockey_limit"), g_iDefJockeyLimit);
    SetConVarInt(FindConVar("z_charger_limit"), g_iDefChargerLimit);
    
    SetConVarFloat(FindConVar("survivor_friendly_fire_factor_normal"), g_fDefFFFactor);
    SetConVarInt(FindConVar("z_tank_health"), g_iDefTankHealth);
    SetConVarInt(FindConVar("z_frustration_lifetime"), g_iDefTankFrustTime);
    
    SetConVarInt(FindConVar("sv_force_time_of_day"), -1);
}

EVENT_ResetDifficulty()
{
    // reset any changes to cvars related to map difficulty
    
    // common
    SetConVarInt(FindConVar("z_common_limit"), g_iDefCommonLimit);
    SetConVarInt(FindConVar("z_background_limit"), g_iDefBackgroundLimit);
    SetConVarInt(FindConVar("z_mob_spawn_min_size"), g_iDefHordeSizeMin);
    SetConVarInt(FindConVar("z_mob_spawn_max_size"), g_iDefHordeSizeMax);
    SetConVarInt(FindConVar("z_mob_spawn_min_interval_normal"), g_iDefHordeTimeMin);
    SetConVarInt(FindConVar("z_mob_spawn_max_interval_normal"), g_iDefHordeTimeMax);
    
    // SI
    SetConVarInt(FindConVar("z_ghost_delay_min"), g_iDefSpawnTimeMin);
    SetConVarInt(FindConVar("z_ghost_delay_max"), g_iDefSpawnTimeMax);
}

EVENT_SetDifficulty(commonDiff, specialDiff)
{
    // set the map's difficulty (for balancing special event rounds
    // common = whether to change common cvars
    // special = whether to change special infected cvars

    // difficulty change for specials
    switch (specialDiff)
    {
        case DIFFICULTY_VERYEASY: {
            SetConVarInt(FindConVar("z_ghost_delay_min"), RoundFloat(float(g_iDefSpawnTimeMin) * EVENT_VERYEASY_SITIME));
            SetConVarInt(FindConVar("z_ghost_delay_max"), RoundFloat(float(g_iDefSpawnTimeMax) * EVENT_VERYEASY_SITIME));
        }
        case DIFFICULTY_EASY: {
            SetConVarInt(FindConVar("z_ghost_delay_min"), RoundFloat(float(g_iDefSpawnTimeMin) * EVENT_EASY_SITIME));
            SetConVarInt(FindConVar("z_ghost_delay_max"), RoundFloat(float(g_iDefSpawnTimeMax) * EVENT_EASY_SITIME));
        }
        case DIFFICULTY_HARD: {
            SetConVarInt(FindConVar("z_ghost_delay_min"), RoundFloat(float(g_iDefSpawnTimeMin) * EVENT_HARD_SITIME));
            SetConVarInt(FindConVar("z_ghost_delay_max"), RoundFloat(float(g_iDefSpawnTimeMax) * EVENT_HARD_SITIME));
        }
        case DIFFICULTY_VERYHARD: {
            SetConVarInt(FindConVar("z_ghost_delay_min"), RoundFloat(float(g_iDefSpawnTimeMin) * EVENT_VERYHARD_SITIME));
            SetConVarInt(FindConVar("z_ghost_delay_max"), RoundFloat(float(g_iDefSpawnTimeMax) * EVENT_VERYHARD_SITIME));
        }
        
    }
    
    // difficulty change for commons
    switch (commonDiff)
    {
        // set common level to easy
        case DIFFICULTY_SUPEREASY: {
            SetConVarInt(FindConVar("z_common_limit"), RoundFloat(float(g_iDefCommonLimit) * EVENT_SUPEREASY_CILIM));
            SetConVarInt(FindConVar("z_background_limit"), RoundFloat(float(g_iDefBackgroundLimit) * EVENT_SUPEREASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_size"), RoundFloat(float(g_iDefHordeSizeMin) * EVENT_SUPEREASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_size"), RoundFloat(float(g_iDefHordeSizeMax) * EVENT_SUPEREASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_interval_normal"), RoundFloat(float(g_iDefHordeTimeMin) / EVENT_VERYEASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_interval_normal"), RoundFloat(float(g_iDefHordeTimeMax) / EVENT_VERYEASY_CILIM));
        }
        
        case DIFFICULTY_VERYEASY: {
            SetConVarInt(FindConVar("z_common_limit"), RoundFloat(float(g_iDefCommonLimit) * EVENT_VERYEASY_CILIM));
            SetConVarInt(FindConVar("z_background_limit"), RoundFloat(float(g_iDefBackgroundLimit) * EVENT_VERYEASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_size"), RoundFloat(float(g_iDefHordeSizeMin) * EVENT_VERYEASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_size"), RoundFloat(float(g_iDefHordeSizeMax) * EVENT_VERYEASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_interval_normal"), RoundFloat(float(g_iDefHordeTimeMin) / EVENT_EASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_interval_normal"), RoundFloat(float(g_iDefHordeTimeMax) / EVENT_EASY_CILIM));
        }
        
        case DIFFICULTY_EASY: {
            SetConVarInt(FindConVar("z_common_limit"), RoundFloat(float(g_iDefCommonLimit) * EVENT_EASY_CILIM));
            SetConVarInt(FindConVar("z_background_limit"), RoundFloat(float(g_iDefBackgroundLimit) * EVENT_EASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_size"), RoundFloat(float(g_iDefHordeSizeMin) * EVENT_EASY_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_size"), RoundFloat(float(g_iDefHordeSizeMax) * EVENT_EASY_CILIM));
        }
        case DIFFICULTY_HARD: {
            SetConVarInt(FindConVar("z_common_limit"), RoundFloat(float(g_iDefCommonLimit) * EVENT_HARD_CILIM));
            SetConVarInt(FindConVar("z_background_limit"), RoundFloat(float(g_iDefBackgroundLimit) * EVENT_HARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_size"), RoundFloat(float(g_iDefHordeSizeMin) * EVENT_HARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_size"), RoundFloat(float(g_iDefHordeSizeMax) * EVENT_HARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_interval_normal"), RoundFloat(float(g_iDefHordeTimeMax) / EVENT_HARD_CILIM));
        }
        
        case DIFFICULTY_VERYHARD: {
            SetConVarInt(FindConVar("z_common_limit"), RoundFloat(float(g_iDefCommonLimit) * EVENT_VERYHARD_CILIM));
            SetConVarInt(FindConVar("z_background_limit"), RoundFloat(float(g_iDefBackgroundLimit) * EVENT_VERYHARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_size"), RoundFloat(float(g_iDefHordeSizeMin) * EVENT_VERYHARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_size"), RoundFloat(float(g_iDefHordeSizeMax) * EVENT_VERYHARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_min_interval_normal"), RoundFloat(float(g_iDefHordeTimeMin) / EVENT_VERYHARD_CILIM));
            SetConVarInt(FindConVar("z_mob_spawn_max_interval_normal"), RoundFloat(float(g_iDefHordeTimeMax) / EVENT_VERYHARD_CILIM));
        }
    }
}

EVENT_RoundStartPreparation()
{
    // apply some settings for special events at round start
    
    switch (_:g_iSpecialEvent)
    {
        case EVT_DEFIB: {
            // start out black and white
            for (new i=1; i <= MaxClients; i++) {
                if (IsSurvivor(i)) {
                    
                    SetEntProp(i, Prop_Send, "m_bIsOnThirdStrike", 1);
                    SetEntProp(i, Prop_Send, "m_isGoingToDie", 1);
                }
            }
        }
        
        case EVT_ADREN: {
            /*
                don't do this here:
                it would make survivors bleed out even in readyup...
            
            // start out with bleeding health
            for (new i=1; i <= MaxClients; i++) {
                if (IsSurvivor(i)) {
                    SetEntityHealth(i, 1);
                    SetEntPropFloat(i, Prop_Send, "m_healthBuffer", 100.0);
                }
            }
            */
        }
    }
}

EVENT_SurvivorsLeftSaferoom()
{
    switch (_:g_iSpecialEvent)
    {
        case EVT_ADREN: {
            // makes survivors start with 99 bleeding health
            for (new i=1; i <= MaxClients; i++) {
                if (IsSurvivor(i)) {
                    SetEntityHealth(i, 1);
                    SetEntPropFloat(i, Prop_Send, "m_healthBuffer", 99.0);
                }
            }
        }
        
        case EVT_NOHUD: {
            // no huds for survivors this round
            EVENT_HUDRemoveSurvivors();
        }
        
        case EVT_KEYMASTER: {
            EVENT_PickKeyMaster();
        }
    }
}

EVENT_HUDRemoveSurvivors()
{
    for (new i=1; i <= MaxClients; i++) {
        if (IsSurvivor(i)) {
            HUDRemoveClient(i);
        }
    }
}

EVENT_HUDRestoreAll()
{
    for (new i=1; i <= MaxClients; i++) {
        if (IsClientAndInGame(i)) {
            HUDRestoreClient(i);
        }
    }
}

HUDRemoveClient(client)
{
    if (IsFakeClient(client)) { return; }
    SetEntProp(client, Prop_Send, "m_iHideHUD", EVENT_NOHUD_MASK);
}
HUDRestoreClient(client)
{
    if (IsFakeClient(client)) { return; }
    SetEntProp(client, Prop_Send, "m_iHideHUD", 0);
}


EVENT_ReportPenalty(client=-1)
{
    switch (_:g_iSpecialEvent)
    {
        case EVT_PEN_ITEM: {
            if (client != -1) {
                PrintToChatAll("\x01[\x05r\x01] Item pickup by %N cost \x04%i\x01 points.", client, EVENT_PENALTY_ITEM);
            } else {
                PrintToChatAll("\x01[\x05r\x01] Item pickup cost \x04%i\x01 points.", EVENT_PENALTY_ITEM);
            }
        }
        case EVT_PEN_HEALTH: {
            if (client != -1) {
                PrintToChatAll("\x01[\x05r\x01] Healing by %N cost \x04%i\x01 points.", client, EVENT_PENALTY_HEALTH);
            } else {
                PrintToChatAll("\x01[\x05r\x01] Healing cost \x04%i\x01 points.", EVENT_PENALTY_HEALTH);
            }
        }
        case EVT_PEN_M2: {
            if (client != -1) {
                PrintToChatAll("\x01[\x05r\x01] M2 by %N cost \x04%i\x01 points.", client, EVENT_PENALTY_M2_SI);
            } else {
                PrintToChatAll("\x01[\x05r\x01] M2 cost \x04%i\x01 points.", EVENT_PENALTY_M2_SI);
            }
        }
    }
}

EVENT_DisplayRoundPenalty(client=-1)
{
    switch (_:g_iSpecialEvent)
    {
        case EVT_PEN_ITEM:
        {
            if (client != -1) {
                PrintToChat(client, "\x01[\x05r\x01] \x04Penalty\x01: \x05%i\x01 item pickup%s cost \x04%i\x01 points.", g_iBonusCount, (g_iBonusCount == 1) ? "" : "s", EVENT_PENALTY_ITEM * g_iBonusCount);
            } else {
                PrintToChatAll("\x01[\x05r\x01] \x04Penalty\x01: \x05%i\x01 item pickup%s cost \x04%i\x01 points.", g_iBonusCount, (g_iBonusCount == 1) ? "" : "s", EVENT_PENALTY_ITEM * g_iBonusCount);
            }
        }
        case EVT_PEN_HEALTH:
        {
            if (client != -1) {
                PrintToChat(client, "\x01[\x05r\x01] \x04Penalty\x01: \x05%i\x01 healing action%s cost \x04%i\x01 points.", g_iBonusCount, (g_iBonusCount == 1) ? "" : "s", EVENT_PENALTY_HEALTH * g_iBonusCount);
            } else {
                PrintToChatAll("\x01[\x05r\x01] \x04Penalty\x01: \x05%i\x01 healing action%s cost \x04%i\x01 points.", g_iBonusCount, (g_iBonusCount == 1) ? "" : "s", EVENT_PENALTY_HEALTH * g_iBonusCount);
            }
        }
        case EVT_PEN_M2:
        {
            if (client != -1) {
                PrintToChat(client, "\x01[\x05r\x01] \x04Penalty\x01: \x05%i\x01 m2%s cost \x04%i\x01 points.", g_iBonusCount, (g_iBonusCount == 1) ? "" : "s", EVENT_PENALTY_M2_SI * g_iBonusCount);
            } else {
                PrintToChatAll("\x01[\x05r\x01] \x04Penalty\x01: \x05%i\x01 m2%s cost \x04%i\x01 points.", g_iBonusCount, (g_iBonusCount == 1) ? "" : "s", EVENT_PENALTY_M2_SI * g_iBonusCount);
            }
        }
    }
}



// magic guns wap
EVENT_SwapSurvivorGun(client)
{
    if (!IsClientAndInGame(client) || !IsPlayerAlive(client)) { return; }
    
    // swap out old weapon, if any
    new weaponIndex = GetPlayerWeaponSlot(client, PLAYER_SLOT_PRIMARY);
    if (weaponIndex > -1 && IsValidEdict(weaponIndex))
    {
        RemovePlayerItem(client, weaponIndex);
        RemoveEdict(weaponIndex);
    }
    
    // pick new weapon (random)
    new ammo = 0;
    new ammoOffset = -1;
    new String:weaponname[STR_MAX_ITEMGIVEN] = "";
    
    new randomPick = GetRandomInt(0, 7);            // disabled t3 for now
    
    if (randomPick < 4) { randomPick = 0; }         // t1 4x
    else if (randomPick < 6) { randomPick = 4; }    // sniper 2x
    else if (randomPick < 8) { randomPick = 6; }    // t2 2x
    
    switch (randomPick)
    {
        case 0:     // t1
        {
            if (GetRandomInt(0,1) == 0) {   // smg
                ammo = 50;
                ammoOffset = SMG_OFFSET_IAMMO;
                
                randomPick = GetRandomInt(0, 2);
                switch (randomPick) {
                    case 0: { weaponname = "weapon_smg"; }
                    case 1: { weaponname = "weapon_smg_silenced"; } 
                    case 2: { weaponname = "weapon_smg_mp5"; } 
                }
            } else {                // shotgun
                ammo = 8;
                ammoOffset = SHOTGUN_OFFSET_IAMMO;
                
                randomPick = GetRandomInt(0, 1);
                switch (randomPick) {
                    case 0: { weaponname = "weapon_pumpshotgun"; }
                    case 1: { weaponname = "weapon_shotgun_chrome"; } 
                }
            }
        }
        case 4:     // sniper
        {
            ammo = 15;
            
            randomPick = GetRandomInt(0, 3);
            switch (randomPick) {
                case 0: { weaponname = "weapon_hunting_rifle"; ammoOffset = SNIPER_OFFSET_IAMMO; }
                case 1: { weaponname = "weapon_sniper_scout"; ammoOffset = MILITARY_SNIPER_OFFSET_IAMMO; }
                case 2: { weaponname = "weapon_sniper_military"; ammoOffset = MILITARY_SNIPER_OFFSET_IAMMO; ammo = 20; } 
                case 3: { weaponname = "weapon_sniper_awp"; ammoOffset = MILITARY_SNIPER_OFFSET_IAMMO; } 
            }
        }
        case 6:     // t2
        {
            if (GetRandomInt(0,1) == 0) {   // rifle
                ammoOffset = ASSAULT_RIFLE_OFFSET_IAMMO;
                
                randomPick = GetRandomInt(0, 3);
                switch (randomPick) {
                    case 0: { weaponname = "weapon_rifle"; ammo = 50; }
                    case 1: { weaponname = "weapon_rifle_ak47"; ammo = 40; } 
                    case 2: { weaponname = "weapon_rifle_desert"; ammo = 60; } 
                    case 3: { weaponname = "weapon_rifle_sg552"; ammo = 50; } 
                }
            } else {                // shotgun
                ammo = 10;
                ammoOffset = AUTO_SHOTGUN_OFFSET_IAMMO;
                
                randomPick = GetRandomInt(0, 1);
                switch (randomPick) {
                    case 0: { weaponname = "weapon_autoshotgun"; }
                    case 1: { weaponname = "weapon_shotgun_spas"; } 
                }
            }
        }
        case 8:     // t3
        {
            // note: m60 can't do ammo offset, use weapon's m_iClip1 netprop instead
            // GL should work pretty much as normal
        }
    
    }
    
    // experiment: give gun but force client to reload that gun!
    // give weapon and remember
    g_iArGunAmmoCount[client] = ammo;
    new ent = GiveItem(client, weaponname, ammo, ammoOffset);
    
    // set clip size to what we set above
    SetEntProp(ent, Prop_Send, "m_iClip1", 0, 4);
}

public Action: Timer_CheckSurvivorGun(Handle:timer, any:client)
{
    EVENT_CheckSurvivorGun(client);
}

EVENT_CheckSurvivorGun(client)
{
    // check after team switch / player join
    // reset available ammo during gunswap event
    new ammo = 0;
    
    // swap out old weapon, if any
    new weaponIndex = GetPlayerWeaponSlot(client, PLAYER_SLOT_PRIMARY);
    if (weaponIndex < 1 || !IsValidEdict(weaponIndex)) {
        EVENT_SwapSurvivorGun(client);
        return;
    }
    
    ammo = GetEntProp(weaponIndex, Prop_Send, "m_iClip1");
    
    // check weapon ammo at offset
    new iOffset = -1;
    new String:classname[128];
    GetEdictClassname(weaponIndex, classname, sizeof(classname));
    
    if ( StrEqual("weapon_smg", classname, false) || StrEqual("weapon_smg_silenced", classname, false) || StrEqual("weapon_smg_mp5", classname, false) ) {
        iOffset = SMG_OFFSET_IAMMO;
    } else if ( StrEqual("weapon_pumpshotgun", classname, false) || StrEqual("weapon_shotgun_chrome", classname, false) ) {
        iOffset = SHOTGUN_OFFSET_IAMMO;
    } else if ( StrEqual("weapon_rifle", classname, false) || StrEqual("weapon_rifle_ak47", classname, false) || StrEqual("weapon_rifle_desert", classname, false) || StrEqual("weapon_rifle_sg552", classname, false)) {
        iOffset = ASSAULT_RIFLE_OFFSET_IAMMO;
    } else if ( StrEqual("weapon_autoshotgun", classname, false) || StrEqual("weapon_shotgun_spas", classname, false) ) {
        iOffset = AUTO_SHOTGUN_OFFSET_IAMMO;
    } else if ( StrEqual("weapon_hunting_rifle", classname, false) ) {
        iOffset = SNIPER_OFFSET_IAMMO;
    } else if ( StrEqual("weapon_sniper_military", classname, false) || StrEqual("weapon_sniper_scout", classname, false) || StrEqual("weapon_sniper_awp", classname, false) ) {
        iOffset = MILITARY_SNIPER_OFFSET_IAMMO;
    } else if ( StrEqual("weapon_grenade_launcher", classname, false) ) {
        iOffset = GRENADE_LAUNCHER_OFFSET_IAMMO;
    }

    if (iOffset != -1) {
        new iAmmoOffset = FindDataMapOffs(client, "m_iAmmo");
        ammo += GetEntData(client, (iAmmoOffset + iOffset));
    }
    
    if (ammo == 0) {
        EVENT_SwapSurvivorGun(client);
    } else {
        g_iArGunAmmoCount[client] = ammo;
    }
}




// keymaster
public Action: Timer_CheckKeyMaster(Handle:timer)
{
    if (!g_iKeyMaster || !IsClientAndInGame(g_iKeyMaster) || !IsSurvivor(g_iKeyMaster) || !IsPlayerAlive(g_iKeyMaster) || IsFakeClient(g_iKeyMaster))
    {
        EVENT_PickKeyMaster();
    }
}

EVENT_PickKeyMaster(notClient=-1)
{
    // survivors
    new count = 0;
    new survivors[TEAM_SIZE];
    
    for (new i=1; i <= MaxClients; i++)
    {
        if (i != notClient && IsClientInGame(i) && IsSurvivor(i) && IsPlayerAlive(i) && !IsFakeClient(i))
        {
            survivors[count] = i;
            count++;
        }
    }
    
    if (!count) { g_iKeyMaster = 0; return; }
    
    // pick one at random
    new pick = GetRandomInt(0, count-1);
    
    g_iKeyMaster = survivors[pick];
    
    PrintToChatAll("\x01[\x05r\x01] New keymaster: only \x05%N\x01 can open doors.", g_iKeyMaster);
}

// Stabby's multi-witch stuff
// ===========================================================================

SUPPORT_MultiWitchRandomization()
{
    // how many witches (attempt to spawn, not guaranteed)
    g_iWitchNum = GetRandomInt(MULTIWITCH_MIN, MULTIWITCH_MAX);
    
    PrintDebug("[rand] Multi-witch: trying to set %i witches... ", g_iWitchNum);
    
    // find random spots for multiple witches to spawn in
    new Float: flowMin = MULTIWITCH_FLOW_MIN;
    new Float: flowSection = (MULTIWITCH_FLOW_MAX - MULTIWITCH_FLOW_MIN) / g_iWitchNum;
    
    new index = 0;
    
    for (new i = 0; i < g_iWitchNum; i++)
    {
        // find a spot
        if (flowMin > MULTIWITCH_FLOW_MAX) { continue; }
        if (flowMin + flowSection > MULTIWITCH_FLOW_MAX) { flowSection = MULTIWITCH_FLOW_MAX - flowMin; }
            
        new Float: tmpSpot = GetRandomFloat(flowMin, flowMin + flowSection);
        
        // safeguard
        if (tmpSpot > MULTIWITCH_FLOW_MAX) { tmpSpot = MULTIWITCH_FLOW_MAX; }
        
        // only set witch if a tank doesn't spawn near
        if (g_bTankWillSpawn && FloatAbs( L4D2Direct_GetVSTankFlowPercent( (g_bSecondHalf) ? 1 : 0 ) - tmpSpot) < MULTIWITCH_FLOW_TANK ) {
            
            flowMin = L4D2Direct_GetVSTankFlowPercent( (g_bSecondHalf) ? 1 : 0 ) + MULTIWITCH_FLOW_TANK;
            
            PrintDebug("[rand] Multi-witch near tank spawn, blocked: %.2f near %.2f (next one possible at %.2f)", tmpSpot, L4D2Direct_GetVSTankFlowPercent( (g_bSecondHalf) ? 1 : 0 ), flowMin );
            
            if (g_iWitchNum - index - 1 > 0 ) {
                flowSection = (MULTIWITCH_FLOW_MAX - flowMin) / (g_iWitchNum - index - 1);
            }
            continue;
        }
        
        // store in array
        g_fArWitchFlows[index] = tmpSpot;
        g_bArWitchSitting[index] = (GetRandomInt(0,3) == 0) ? false : true;
        
        PrintDebug("[rand] Multi-witch [%i] to spawn at: %f (%s)", index, g_fArWitchFlows[index], (g_bArWitchSitting[index]) ? "sitting" : "walking");
        
        index++;
        flowMin = tmpSpot + MULTIWITCH_FLOW_BETWEEN;
    }
    
    g_iWitchNum = index;    // set to actual number set to spawn
}

SUPPORT_MultiWitchRoundPrep()
{
    //PrintDebug("[rand] Multi-witch round prep [%i]...", g_bMultiWitch);
    g_iWitchIndex = 0;
    
    // prepare multi-witch for round
    if (g_bMultiWitch)
    {
        PrintDebug("[rand] Multi-witch: setting first spawn (%.2f)", g_fArWitchFlows[0]);
        //both rounds because I remember there being weirdness with this native
        L4D2Direct_SetVSWitchToSpawnThisRound(0, true);
        L4D2Direct_SetVSWitchToSpawnThisRound(1, true);
        
        // set first witch
        L4D2Direct_SetVSWitchFlowPercent(0, g_fArWitchFlows[0]);
        L4D2Direct_SetVSWitchFlowPercent(1, g_fArWitchFlows[0]);
        
        g_iWitchIndex++;
    }
}

public Action:L4D_OnSpawnWitch(const Float:vector[3], const Float:qangle[3])
{
    if (g_bMultiWitch)
    {
        CreateTimer(1.0, Timer_PrepareNextWitch, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action: Timer_PrepareNextWitch(Handle:timer)
{
    if (g_iWitchIndex == g_iWitchNum - 1)
    {
        //g_fWitchIndex = -1;    //no witches left: could be useful knowledge for other functions?
        return;
    }
    
    L4D2Direct_SetVSWitchToSpawnThisRound(0, true);
    L4D2Direct_SetVSWitchToSpawnThisRound(1, true);    
    L4D2Direct_SetVSWitchFlowPercent(0, g_fArWitchFlows[g_iWitchIndex]);
    L4D2Direct_SetVSWitchFlowPercent(1, g_fArWitchFlows[g_iWitchIndex]);
    
    if (g_bArWitchSitting[g_iWitchIndex]) {
        SetConVarInt(FindConVar("sv_force_time_of_day"), WITCHES_NIGHT);
    } else {
        SetConVarInt(FindConVar("sv_force_time_of_day"), WITCHES_DAY);
    }
    
    g_iWitchIndex++;
}

// ===========================================================================
//  Double-tank && minitanks
public Action: Timer_PrepareNextTank(Handle:timer)
{
    if (_:g_iSpecialEvent == EVT_MINITANKS)
    {
        if (g_iMiniTankIndex == g_iMiniTankNum - 1) {
            return;
        }
        
        L4D2Direct_SetVSTankToSpawnThisRound(0, true);
        L4D2Direct_SetVSTankToSpawnThisRound(1, true);
        L4D2Direct_SetVSTankFlowPercent(0, g_fArMiniTankFlows[g_iMiniTankIndex]);
        L4D2Direct_SetVSTankFlowPercent(1, g_fArMiniTankFlows[g_iMiniTankIndex]);
        
        g_iMiniTankIndex++;
    }
    else        // 'normal' doubletank
    {
        L4D2Direct_SetVSTankToSpawnThisRound(0, true);
        L4D2Direct_SetVSTankToSpawnThisRound(1, true);
        L4D2Direct_SetVSTankFlowPercent(0, g_fTankFlowLate);
        L4D2Direct_SetVSTankFlowPercent(1, g_fTankFlowLate);
    }
}

SUPPORT_MultiTankRandomization()
{
    // how many tanks
    g_iMiniTankNum = MINITANKS_NUM;
    
    PrintDebug("[rand] Multi-tank: trying to set %i tanks... ", g_iMiniTankNum);
    
    // find random spots for multiple witches to spawn in
    new index = 0;
    for (new i = 0; i < g_iMiniTankNum; i++)
    {
        new Float: tmpSpot = MINITANKS_FLOW_MIN + (float(i) * MINITANKS_FLOW_INT) + GetRandomFloat( -1 * MINITANKS_FLOW_VAR, MINITANKS_FLOW_VAR);
        
        // safeguard
        if (tmpSpot < MINITANKS_FLOW_MIN) { tmpSpot = MINITANKS_FLOW_MIN; }
        else if (tmpSpot > MINITANKS_FLOW_MAX) { tmpSpot = MINITANKS_FLOW_MAX; }
        
        // store in array
        g_fArMiniTankFlows[index] = tmpSpot;
        
        PrintDebug("[rand] Multi/mini-tank [%i] to spawn at: %f", index, g_fArMiniTankFlows[index]);
        
        index++;
    }
    
    g_iMiniTankNum = index;    // set to actual number set to spawn
}

SUPPORT_MultiTankRoundPrep()
{
    //PrintDebug("[rand] Multi-witch round prep [%i]...", g_bMultiWitch);
    g_iMiniTankIndex = 0;
    
    // prepare multi-witch for round
    if (_:g_iSpecialEvent == EVT_MINITANKS)
    {
        PrintDebug("[rand] Multi-tank: setting first spawn (%.2f)", g_fArMiniTankFlows[0]);
        
        L4D2Direct_SetVSTankToSpawnThisRound(0, true);
        L4D2Direct_SetVSTankToSpawnThisRound(1, true);
        
        // set first tank
        L4D2Direct_SetVSTankFlowPercent(0, g_fArMiniTankFlows[0]);
        L4D2Direct_SetVSTankFlowPercent(1, g_fArMiniTankFlows[0]);
        
        g_iMiniTankIndex++;
    }
}

// ===========================================================================


/*
    Support functions, general
    --------------------------
    Actually: any general function
    that I probably won't touch
    ever again
*/

public PrintDebug(const String:Message[], any:...)
{
    #if DEBUG_MODE
        decl String:DebugBuff[256];
        VFormat(DebugBuff, sizeof(DebugBuff), Message, 2);
        LogMessage(DebugBuff);
        //PrintToServer(DebugBuff);
        //PrintToChatAll(DebugBuff);
    #endif
}

// cheat command
CheatCommand(client, const String:command[], const String:arguments[])
{
    if (!client) return;
    new admindata = GetUserFlagBits(client);
    SetUserFlagBits(client, ADMFLAG_ROOT);
    new flags = GetCommandFlags(command);
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);
    FakeClientCommand(client, "%s %s", command, arguments);
    SetCommandFlags(command, flags);
    SetUserFlagBits(client, admindata);
}

bool: SUPPORT_IsWeaponPrimary(weapId)
{
    switch (_:weapId)
    {
        case WEPID_SMG: { return true; }
        case WEPID_PUMPSHOTGUN: { return true; }
        case WEPID_AUTOSHOTGUN: { return true; }
        case WEPID_RIFLE: { return true; }
        case WEPID_HUNTING_RIFLE: { return true; }
        case WEPID_SMG_SILENCED: { return true; }
        case WEPID_SHOTGUN_CHROME: { return true; }
        case WEPID_RIFLE_DESERT: { return true; }
        case WEPID_SNIPER_MILITARY: { return true; }
        case WEPID_SHOTGUN_SPAS: { return true; }
        case WEPID_GRENADE_LAUNCHER: { return true; }
        case WEPID_RIFLE_AK47: { return true; }
        case WEPID_SMG_MP5: { return true; }
        case WEPID_RIFLE_SG552: { return true; }
        case WEPID_SNIPER_AWP: { return true; }
        case WEPID_SNIPER_SCOUT: { return true; }
        case WEPID_RIFLE_M60: { return true; }
    }
    return false;
}

bool: SUPPORT_IsInReady()
{
    // do a check that's compatible with new and old readyup plugins
    
    // check if we've readyup loaded (here because now all plugins are loaded)
    if (g_hCvarReadyUp == INVALID_HANDLE || !GetConVarBool(g_hCvarReadyUp)) { return false; }
    
    // find a survivor
    new client = GetSpawningClient(true);
    if (client == 0) { return false; }
    
    // if he's frozen, assume it's readyup time
    return bool: (GetEntityMoveType(client) == MOVETYPE_NONE);
}

bool: IsEntityInSaferoom(entity, bool:isPlayer=false, bool:endSaferoom=true)
{
    // 1. is it held by someone (we're only calling this at round end by default?
    
    if (isPlayer) {
        if (endSaferoom) {
            return bool: SAFEDETECT_IsPlayerInEndSaferoom(entity);
        } else {
            return bool: SAFEDETECT_IsPlayerInStartSaferoom(entity);
        }
    }
    
    // entity
    if (endSaferoom) {
        return bool: SAFEDETECT_IsEntityInEndSaferoom(entity);
    } else {
        return bool: SAFEDETECT_IsEntityInStartSaferoom(entity);
    }
}


// get just any survivor client (param = false = switch to infected too)
GetSpawningClient(bool:onlySurvivors=false)
{
    for (new i=1; i <= GetMaxClients(); i++) {
        if (IsClientConnected(i) && IsSurvivor(i) && !IsFakeClient(i)) { return i; }
    }
    
    if (onlySurvivors) { return 0; }
    
    // since we're just using this for spawning stuff that requires a client, use infected alternatively
    for (new i=1; i <= GetMaxClients(); i++) {
        if (IsClientConnected(i) && IsInfected(i) && !IsFakeClient(i)) { return i; }
    }
    
    // no usable clients...
    return 0;
}

bool: IsClientAndInGame(index) return (index > 0 && index <= MaxClients && IsClientInGame(index));
bool: IsSurvivor(client)
{
    if (IsClientAndInGame(client)) {
        return GetClientTeam(client) == TEAM_SURVIVOR;
    }
    return false;
}
bool: IsInfected(client)
{
    if (IsClientAndInGame(client)) {
        return GetClientTeam(client) == TEAM_INFECTED;
    }
    return false;
}
bool: IsTank(any:client)
{
    new iClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (IsPlayerAlive(client) && iClass == ZC_TANK) { return true; }
    return false;
}


ForceRandomTankPlayer()
{
    for (new i = 1; i < MaxClients+1; i++) {
        if (!IsClientConnected(i) || !IsClientInGame(i)) {
            continue;
        }

        if (IsInfected(i)) {
            // set the same tickets for everyone
            L4D2Direct_SetTankTickets(i, 5);
        }
    }
}


/*
GetTankClient()
{
    if (!g_bIsTankInPlay) return 0;
    new tankclient = g_iTankClient;
 
    if (!IsClientInGame(tankclient))
    {
        tankclient = FindTankClient();
        if (!tankclient) return 0;
        g_iTankClient = tankclient;
    }
    return tankclient;
}
*/

FindTankClient()
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) ||
            GetClientTeam(client) != TEAM_INFECTED ||
            !IsPlayerAlive(client) ||
            GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_TANK)
            continue;

        return client;
    }
    return 0;
}

bool: IsPlayerGhost(any:client)
{
    if (GetEntProp(client, Prop_Send, "m_isGhost")) { return true; }
    return false;
}


/*
bool: IsCommon(entity)
{
    if (entity <= 0 || entity > 2048 || !IsValidEdict(entity)) return false;
    
    decl String:model[128];
    GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
    
    if (StrContains(model, "_ceda") != -1)      { return false; }
    if (StrContains(model, "_clown") != -1)     { return false; }
    if (StrContains(model, "_mud") != -1)       { return false; }
    if (StrContains(model, "_riot") != -1)      { return false; }
    if (StrContains(model, "_roadcrew") != -1)  { return false; }
    if (StrContains(model, "_jimmy") != -1)     { return false; }
    return true;
}
*/

AnyoneLoadedIn()
{
    // see if there are humans on the server
    for (new i=1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR && !IsFakeClient(i))  {
            return true;
        }
    }
    return false;
}

CountInfectedClass(any:ZClass, ignoreClient)
{
    // note: ghosts are considered 'alive', so return IsPlayerAlive() true too.
    
    // counts infected currently spawned/ghosted
    new classCount = 0, classType;

    for (new i=1; i <= MaxClients; i++)
    {
        if (i == ignoreClient) { continue; }                                // so it doesn't count the client's class that it is about to change..
        if (IsClientInGame(i) && GetClientTeam(i) == TEAM_INFECTED)
        {
            if ( IsPlayerAlive(i) )
            {
                classType = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (classType == ZClass) { classCount++; }
            }
        }
    }
    return classCount;
}

// give an item to a player
GiveItem(client, String:item[STR_MAX_ITEMGIVEN], ammo, iOffset)
{
    // new approach
    decl entity;
    decl Float:clientOrigin[3];

    entity = CreateEntityByName(item);
    
    if (!IsValidEntity(entity)) {
        PrintDebug("[rand] error: no valid entity for spawning: %s", item);
        return -1;
    }
    
    GetClientAbsOrigin(client, clientOrigin);
    TeleportEntity(entity, clientOrigin, NULL_VECTOR, NULL_VECTOR);
    
    DispatchSpawn(entity);
    
    if (!ammo && StrEqual(item, "weapon_pistol")) {
        AcceptEntityInput(entity, "use", client);
    } else {
        EquipPlayerWeapon(client, entity);
        
        if (ammo > -1)
        {
            new iAmmoOffset = FindDataMapOffs(client, "m_iAmmo");
            SetEntData(client, (iAmmoOffset + iOffset), ammo);
        }
        else
        {
            new iAmmoOffset = FindDataMapOffs(client, "m_iAmmo");
            SetEntData(client, (iAmmoOffset + iOffset), 0);
        }
    }
    
    return entity;
}

GiveItemMelee(client, String:item[MELEE_CLASS_LENGTH])
{
    // new approach
    decl entity;
    decl Float:clientOrigin[3];

    entity = CreateEntityByName("weapon_melee");
    
    if (!IsValidEntity(entity)) {
        PrintDebug("[rand] error: no valid entity for spawning: %s", item);
        return;
    }
    
    GetClientAbsOrigin(client, clientOrigin);
    TeleportEntity(entity, clientOrigin, NULL_VECTOR, NULL_VECTOR);
    DispatchKeyValue(entity, "melee_script_name", item);
    
    DispatchSpawn(entity);
    EquipPlayerWeapon(client, entity);
}


// throw molotov
/*
public ThrowMolotov(i_Client)
{
    decl i_Ent, Float:f_Origin[3], Float:f_Speed[3], Float:f_Angles[3], String:s_TargetName[32], Float:f_CvarSpeed, String:s_Ent[4];
    
    i_Ent = CreateEntityByName("molotov_projectile");
    
    if (IsValidEntity(i_Ent)) {
        SetEntPropEnt(i_Ent, Prop_Data, "m_hOwnerEntity", i_Client);
        SetEntityModel(i_Ent, MODEL_W_MOLOTOV);
        FormatEx(s_TargetName, sizeof(s_TargetName), "molotov%d", i_Ent);
        DispatchKeyValue(i_Ent, "targetname", s_TargetName);
        DispatchSpawn(i_Ent);
    }
    
    g_ThrewGrenade[i_Client] = i_Ent;

    GetClientEyePosition(i_Client, f_Origin);
    GetClientEyeAngles(i_Client, f_Angles);
    GetAngleVectors(f_Angles, f_Speed, NULL_VECTOR, NULL_VECTOR);
    f_CvarSpeed = GetConVarFloat(h_CvarMolotovSpeed);
    
    f_Speed[0] *= f_CvarSpeed;
    f_Speed[1] *= f_CvarSpeed;
    f_Speed[2] *= f_CvarSpeed;
    
    GetRandomAngles(f_Angles);
    TeleportEntity(i_Ent, f_Origin, f_Angles, f_Speed);
    EmitSoundToAll(SOUND_MOLOTOV, 0, SNDCHAN_WEAPON, SNDLEVEL_TRAFFIC, SND_NOFLAGS, SNDVOL_NORMAL, 100, _, f_Origin, NULL_VECTOR, false, 0.0);

    IntToString(i_Ent, s_Ent, sizeof(s_Ent));
    SetTrieValue(g_t_GrenadeOwner, s_Ent, i_Client);
    
    g_h_GrenadeTimer[i_Client] = CreateTimer(0.1, Timer_MolotovThink, i_Ent, TIMER_REPEAT);
}

public Action:Timer_MolotovThink(Handle:h_Timer, any:i_Ent)
{
    decl i_Client, String:s_Ent[4], String:s_ClassName[32];

    IntToString(i_Ent, s_Ent, sizeof(s_Ent));
    GetTrieValue(g_t_GrenadeOwner, s_Ent, i_Client);
    GetEdictClassname(i_Ent, s_ClassName, sizeof(s_ClassName));
    
    if (!IsValidEdict(i_Ent) || StrContains(s_ClassName, "projectile") == -1) {
        if (g_h_GrenadeTimer[i_Client] != INVALID_HANDLE) {
            KillTimer(g_h_GrenadeTimer[i_Client]);
            g_h_GrenadeTimer[i_Client] = INVALID_HANDLE;
            g_ThrewGrenade[i_Client] = 0;
            RemoveFromTrie(g_t_GrenadeOwner, s_Ent);
        }
        
        return Plugin_Handled;
    }
    
    decl Float:f_Origin[3];

    GetEntPropVector(i_Ent, Prop_Send, "m_vecOrigin", f_Origin);
    
    if (0.0 < OnGroundUnits(i_Ent) <= 10.0) {    
        if (g_h_GrenadeTimer[i_Client] != INVALID_HANDLE) {
            KillTimer(g_h_GrenadeTimer[i_Client]);
            g_h_GrenadeTimer[i_Client] = INVALID_HANDLE;
        }    
        
        g_ThrewGrenade[i_Client] = 0;
        RemoveEdict(i_Ent);
        
        i_Ent = CreateEntityByName("prop_physics");
        DispatchKeyValue(i_Ent, "physdamagescale", "0.0");
        DispatchKeyValue(i_Ent, "model", MODEL_GASCAN);
        DispatchSpawn(i_Ent);
        TeleportEntity(i_Ent, f_Origin, NULL_VECTOR, NULL_VECTOR);
        SetEntityMoveType(i_Ent, MOVETYPE_VPHYSICS);
        AcceptEntityInput(i_Ent, "Break");
        
        return Plugin_Continue;
    }
    else
    {
        decl Float:f_Angles[3];
        
        GetRandomAngles(f_Angles);
        TeleportEntity(i_Ent, NULL_VECTOR, f_Angles, NULL_VECTOR);
    }
    
    return Plugin_Continue;
}
*/


// spawning a zombie (cheap way :()
SpawnCommon(client, mobs = 1)
{
    new flags = GetCommandFlags("z_spawn");
    SetCommandFlags("z_spawn", flags & ~FCVAR_CHEAT);
    for(new i=0; i < mobs; i++) {
        FakeClientCommand(client, "z_spawn infected auto");
    }
    SetCommandFlags("z_spawn", flags);
}

// spawning a horde (cheap way.. damnit)
SpawnPanicHorde(client, mobs = 1)
{
    new flags = GetCommandFlags("z_spawn");
    SetCommandFlags("z_spawn", flags & ~FCVAR_CHEAT);
    for(new i=0; i < mobs; i++) {
        FakeClientCommand(client, "z_spawn mob auto");
    }
    SetCommandFlags("z_spawn", flags);
}



// create explosion
CreateExplosion(Float:carPos[3], Float:power, bool:fire = false)
{
    decl String:sRadius[256];
    decl String:sPower[256];
    new Float:flMxDistance = float(EXPLOSION_RADIUS);
    if (!power) { power = EXPLOSION_POWER_LOW; }
    
    IntToString(EXPLOSION_RADIUS, sRadius, sizeof(sRadius));
    IntToString(RoundFloat(power), sPower, sizeof(sPower));
    new exParticle2 = CreateEntityByName("info_particle_system");
    new exParticle3 = CreateEntityByName("info_particle_system");
    new exPhys = CreateEntityByName("env_physexplosion");
    new exTrace = 0;
    new exHurt = CreateEntityByName("point_hurt");
    new exParticle = CreateEntityByName("info_particle_system");
    new exEntity = CreateEntityByName("env_explosion");
    /*new exPush = CreateEntityByName("point_push");*/
    
    //Set up the particle explosion
    DispatchKeyValue(exParticle, "effect_name", EXPLOSION_PARTICLE);
    DispatchSpawn(exParticle);
    ActivateEntity(exParticle);
    TeleportEntity(exParticle, carPos, NULL_VECTOR, NULL_VECTOR);
    
    DispatchKeyValue(exParticle2, "effect_name", EXPLOSION_PARTICLE2);
    DispatchSpawn(exParticle2);
    ActivateEntity(exParticle2);
    TeleportEntity(exParticle2, carPos, NULL_VECTOR, NULL_VECTOR);
    
    DispatchKeyValue(exParticle3, "effect_name", EXPLOSION_PARTICLE3);
    DispatchSpawn(exParticle3);
    ActivateEntity(exParticle3);
    TeleportEntity(exParticle3, carPos, NULL_VECTOR, NULL_VECTOR);
    
    if (fire) {
        exTrace = CreateEntityByName("info_particle_system");
        DispatchKeyValue(exTrace, "effect_name", FIRE_PARTICLE);
        DispatchSpawn(exTrace);
        ActivateEntity(exTrace);
        TeleportEntity(exTrace, carPos, NULL_VECTOR, NULL_VECTOR);
    }
    
    //Set up explosion entity
    DispatchKeyValue(exEntity, "fireballsprite", "sprites/muzzleflash4.vmt");
    DispatchKeyValue(exEntity, "iMagnitude", sPower);
    DispatchKeyValue(exEntity, "iRadiusOverride", sRadius);
    DispatchKeyValue(exEntity, "spawnflags", "828");
    DispatchSpawn(exEntity);
    TeleportEntity(exEntity, carPos, NULL_VECTOR, NULL_VECTOR);
    
    //Set up physics movement explosion
    DispatchKeyValue(exPhys, "radius", sRadius);
    DispatchKeyValue(exPhys, "magnitude", sPower);
    DispatchSpawn(exPhys);
    TeleportEntity(exPhys, carPos, NULL_VECTOR, NULL_VECTOR);
    
    
    //Set up hurt point
    DispatchKeyValue(exHurt, "DamageRadius", sRadius);
    DispatchKeyValue(exHurt, "DamageDelay", "0.5");
    DispatchKeyValue(exHurt, "Damage", "5");
    DispatchKeyValue(exHurt, "DamageType", "8");
    DispatchSpawn(exHurt);
    TeleportEntity(exHurt, carPos, NULL_VECTOR, NULL_VECTOR);
    
    switch(GetRandomInt(1,3)) {
        case 1: {
            if(!IsSoundPrecached(EXPLOSION_SOUND)) { PrecacheSound(EXPLOSION_SOUND); }
            EmitSoundToAll(EXPLOSION_SOUND);
        }
        case 2: {
            if(!IsSoundPrecached(EXPLOSION_SOUND2)) { PrecacheSound(EXPLOSION_SOUND2); }
            EmitSoundToAll(EXPLOSION_SOUND2);
        }
        case 3: {
            if(!IsSoundPrecached(EXPLOSION_SOUND3)) { PrecacheSound(EXPLOSION_SOUND3); }
            EmitSoundToAll(EXPLOSION_SOUND3);
        }
    }
    
    if(!IsSoundPrecached(EXPLOSION_DEBRIS)) {
        PrecacheSound(EXPLOSION_DEBRIS);
    }
    EmitSoundToAll(EXPLOSION_DEBRIS);
    
    //BOOM!
    AcceptEntityInput(exParticle, "Start");
    AcceptEntityInput(exParticle2, "Start");
    AcceptEntityInput(exParticle3, "Start");
    if (fire) { AcceptEntityInput(exTrace, "Start"); }
    AcceptEntityInput(exEntity, "Explode");
    AcceptEntityInput(exPhys, "Explode");
    AcceptEntityInput(exHurt, "TurnOn");
    
    new Handle:pack2 = CreateDataPack();
    WritePackCell(pack2, exParticle);
    WritePackCell(pack2, exParticle2);
    WritePackCell(pack2, exParticle3);
    if (fire) { WritePackCell(pack2, exTrace); } else { WritePackCell(pack2, -1); }
    WritePackCell(pack2, exEntity);
    WritePackCell(pack2, exPhys);
    if (fire) { WritePackCell(pack2, exHurt); } else { WritePackCell(pack2, -1); }
    CreateTimer(EXPLOSION_DURATION + 1.5, Timer_DeleteParticles, pack2, TIMER_FLAG_NO_MAPCHANGE);
    
    if (!fire) { 
        new Handle:pack3 = CreateDataPack();
        WritePackCell(pack3, exHurt);
        CreateTimer(EXPLOSION_DURATION_MIN, Timer_DeleteParticlesMin, pack3, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    if (fire) {
        new Handle:pack = CreateDataPack();
        WritePackCell(pack, exTrace);
        WritePackCell(pack, exHurt);
        CreateTimer(EXPLOSION_DURATION, Timer_StopFire, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    decl Float:survivorPos[3], Float:traceVec[3], Float:resultingFling[3], Float:currentVelVec[3];
    for(new i=1; i<=MaxClients; i++)
    {
        if(!IsClientAndInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SURVIVOR) { continue; }

        GetEntPropVector(i, Prop_Data, "m_vecOrigin", survivorPos);
        
        //Vector and radius distance calcs by AtomicStryker!
        if(GetVectorDistance(carPos, survivorPos) <= flMxDistance)
        {
            MakeVectorFromPoints(carPos, survivorPos, traceVec);                // draw a line from car to Survivor
            GetVectorAngles(traceVec, resultingFling);                            // get the angles of that line
            
            resultingFling[0] = Cosine(DegToRad(resultingFling[1])) * power;    // use trigonometric magic
            resultingFling[1] = Sine(DegToRad(resultingFling[1])) * power;
            resultingFling[2] = power;
            
            GetEntPropVector(i, Prop_Data, "m_vecVelocity", currentVelVec);        // add whatever the Survivor had before
            resultingFling[0] += currentVelVec[0];
            resultingFling[1] += currentVelVec[1];
            resultingFling[2] += currentVelVec[2];
            
            FlingPlayer(i, resultingFling, i);
        }
    }
}

public Action:Timer_StopFire(Handle:timer, Handle:pack)
{
    ResetPack(pack);
    new particle = ReadPackCell(pack);
    new hurt = ReadPackCell(pack);
    CloseHandle(pack);
    
    if (IsValidEntity(particle)) {
        AcceptEntityInput(particle, "Stop");
    }
    
    if (IsValidEntity(hurt)) {
        AcceptEntityInput(hurt, "TurnOff");
    }
}

public Action:Timer_DeleteParticles(Handle:timer, Handle:pack)
{
    ResetPack(pack);
    
    new entity;
    for (new i = 1; i <= 7; i++) {
        entity = ReadPackCell(pack);
        
        if (IsValidEntity(entity)) {
            AcceptEntityInput(entity, "Kill");
        }
    }
    CloseHandle(pack);
}
public Action:Timer_DeleteParticlesMin(Handle:timer, Handle:pack)
{
    ResetPack(pack);
    
    new entity;
    entity = ReadPackCell(pack);
    
    if (IsValidEntity(entity)) {
        AcceptEntityInput(entity, "Kill");
    }
    
    CloseHandle(pack);
}

stock FlingPlayer(target, Float:vector[3], attacker, Float:stunTime = 3.0)
{
    SDKCall(g_CallPushPlayer, target, vector, 76, attacker, stunTime);
}





// fire explosion (trick)
public CreateFire(Float:f_Origin[3], bool:fireWorks)
{
    new i_Ent = CreateEntityByName("prop_physics");
    DispatchKeyValue(i_Ent, "physdamagescale", "0.0");
    if (fireWorks) {
        DispatchKeyValue(i_Ent, "model", MODEL_FIREWORKS);
    } else {
        DispatchKeyValue(i_Ent, "model", MODEL_GASCAN);
    }
    DispatchSpawn(i_Ent);
    TeleportEntity(i_Ent, f_Origin, NULL_VECTOR, NULL_VECTOR);
    SetEntityMoveType(i_Ent, MOVETYPE_VPHYSICS);
    AcceptEntityInput(i_Ent, "Break");
}



Float: FindDistanceFromFloor(entity)
{
    new Float: pos[3];
    new Float: tmpPos[3];
    new Float: floor[3];
    new Float: direction[3];
    new Handle: trace;
    
    direction[0] = 89.0; // downwards
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    
    new bool: bFoundFloor = false;
    new Float: fNewZ = pos[2];
    
    // do a bunch of TRs and save what we find
    for (new i=0; i < 3; i++)
    {
        tmpPos = pos;
        switch (i) {
            case 1: { tmpPos[0] += 3; tmpPos[1] += 3; }
            case 2: { tmpPos[0] -= 3; tmpPos[1] -= 3; }
        }
        
        trace = TR_TraceRayFilterEx(tmpPos, direction, MASK_SOLID, RayType_Infinite, _TraceFilter, entity);
        if (TR_DidHit(trace))
        {
            TR_GetEndPosition(floor, trace);
            if (FloatAbs(pos[2] - floor[2]) && FloatAbs(pos[2] - floor[2]) < MAX_RAYDIF) {
                // if it's absolutely farther away than what we found before, keep it
                if (FloatAbs(pos[2] - floor[2]) > FloatAbs(pos[2] - fNewZ)) {
                    bFoundFloor = true;
                    fNewZ = floor[2];
                }
            }
        }
        if (trace != INVALID_HANDLE) { CloseHandle(trace); }
    }
        
    new Float: fDif = fNewZ;
    
    if (bFoundFloor == false) {          // no floor found, so don't change
        fDif = 0.0;
    } else {
        fDif = pos[2] - fNewZ;
    }
    return fDif;
}

public bool:_TraceFilter(entity, contentsMask, any:data)
{
    // only check if we're not hitting ourselves
    if (!entity || entity == data || !IsValidEntity(entity)) { return false; }
    return true;
}   




/*
    Support, blind infected
    -------------------------- */

public Action:Timer_EntCheck(Handle:timer)
{
    new size = GetArraySize(g_hBlockedEntities);
    decl currentEnt[EntInfo];

    for (new i; i < size; i++)
    {
        GetArrayArray(g_hBlockedEntities, i, currentEnt[0]);
        if (!currentEnt[hasBeenSeen] && IsVisibleToSurvivors(currentEnt[iEntity]))
        {
            //PrintDebug("Unblinding for item %i", i);
            //decl String:tmp[128];
            //GetEntPropString(currentEnt[iEntity], Prop_Data, "m_ModelName", tmp, sizeof(tmp));      // why this? I don't get it, but okay. (try removing it once it works)
            currentEnt[hasBeenSeen] = true;
            SetArrayArray(g_hBlockedEntities, i, currentEnt[0]);
        }
    }
}

public ItemsBlindInfected()
{
    decl bhTemp[EntInfo];
    
    PrintDebug("[rand] Blinding for %i items...", g_iCreatedEntities);
    
    // use list of created items to handle only the entities we need
    for (new i = 0; i < g_iCreatedEntities; i++)
    {
        SDKHook(g_iArCreatedEntities[i], SDKHook_SetTransmit, OnTransmit);
        bhTemp[iEntity] = g_iArCreatedEntities[i];
        bhTemp[hasBeenSeen] = false;
        //PrintDebug("Blinding for item %i", bhTemp[0]);
        PushArrayArray(g_hBlockedEntities, bhTemp[0]);
    }
}

bool:IsVisibleToSurvivors(entity)
{
    new iSurv;

    for (new i = 1; i < MaxClients && iSurv < 4; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVOR) {
            iSurv++;
            if (IsPlayerAlive(i) && IsVisibleTo(i, entity)) {
                return true;
            }
        }
    }

    return false;
}

// check an entity for being visible to a client
bool:IsVisibleTo(client, entity) 
{
    decl Float:vAngles[3], Float:vOrigin[3], Float:vEnt[3], Float:vLookAt[3];
    
    if ( !IsValidEntity(entity) ) {
        //PrintDebug("BlindEntCheck: not a valid entity: %i (client: %N)", entity, client);
        // remove it from blind-check list (by tagging it as 'seen')
        SetBlindEntityAsSeen(entity);
        return false;
    }
    
    // check classname to catch weird predicted_viewmodel problem:
    decl String:classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));
    new entityBlindable: classnameBlindable;
    
    if (GetTrieValue(g_hTrieBlindable, classname, classnameBlindable)) {
        if (classnameBlindable == ENTITY_NOT_BLINDABLE) {
            //PrintDebug("BlindEntCheck: unblindable entity problem: %i (class: %s) (client: %N)", entity, classname, client);
            SetBlindEntityAsSeen(entity);
            return false;
        }
    }
    
    GetClientEyePosition(client,vOrigin);
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vEnt);
    MakeVectorFromPoints(vOrigin, vEnt, vLookAt);
    GetVectorAngles(vLookAt, vAngles);
    
    new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, BlindTraceFilter);
    
    new bool:isVisible = false;
    if (TR_DidHit(trace))
    {
        decl Float:vStart[3];
        TR_GetEndPosition(vStart, trace);
        
        if ((GetVectorDistance(vOrigin, vStart, false) + BLND_TRACE_TOLERANCE) >= GetVectorDistance(vOrigin, vEnt))
        {
            isVisible = true;
        }
    }
    else
    {
        isVisible = true;
    }
    CloseHandle(trace);
    return isVisible;
}

public bool:BlindTraceFilter(entity, contentsMask)
{
    if (entity <= MaxClients || !IsValidEntity(entity)) { return false; }
    
    decl String:class[128];
    GetEdictClassname(entity, class, sizeof(class));
    
    return !StrEqual(class, "prop_physics", false);
}


// this simply sets an entity as visible (basically to be ignored if it causes problems)
public SetBlindEntityAsSeen(entity)
{
    new size = GetArraySize(g_hBlockedEntities);
    decl currentEnt[EntInfo];

    for (new i; i < size; i++)
    {
        GetArrayArray(g_hBlockedEntities, i, currentEnt[0]);
        if (entity == currentEnt[iEntity])
        {
            currentEnt[hasBeenSeen] = true;
            SetArrayArray(g_hBlockedEntities, i, currentEnt[0]);
            break;
        }
    }
}


/*
    L4D2 Storm plugin
    -------------------------- */
    
SUPPORT_StormReset()
{
    new Handle: hTmpCVar = FindConVar("l4d2_storm_allow");
    if (hTmpCVar != INVALID_HANDLE) {
        SetConVarInt(hTmpCVar, 0);
        ServerCommand("sm_stormreset");
        PrintDebug("[rand] Stopped Storm");
    }
    //PrintDebug("storm convar: %i", GetConVarInt(FindConVar("l4d2_storm_allow")));
}

SUPPORT_StormStart()
{
    new Handle: hTmpCVar = FindConVar("l4d2_storm_allow");
    if (hTmpCVar != INVALID_HANDLE) {
        SetConVarInt(hTmpCVar, 1);
        ServerCommand("sm_stormrefresh");
        PrintDebug("[rand] Started Storm");
    }
}





/*
// for debugging blindents
DoBlindEntReport()
{
    PrintDebug("[rand] Randomized item table, for %i items:", g_iStoredEntities);
    
    new String: tmpStr[64];
    new count = 0;
    
    PrintDebug("[rand] --------------- stored entity list -----------------");
    
    for (new i=0; i < g_iStoredEntities; i++)
    {
        // don't show stuff that won't be blinded
        if (g_strArStorage[i][entPickedType] == _:PCK_NOITEM) { continue; }
        if (g_strArStorage[i][entPickedType] == _:PCK_JUNK) { continue; }
        if (g_strArStorage[i][entPickedType] == _:PCK_EXPLOSIVE_BARREL) { continue; }
        if (g_strArStorage[i][entPickedType] == _:PCK_SILLY_GIFT) { continue; }
        
        count++;
        
        if (IsValidEntity(g_strArStorage[i][entNumber])) {
            GetEntityClassname( g_strArStorage[i][entNumber], tmpStr, sizeof(tmpStr) );
        } else {
            tmpStr = "";
        }
        
        PrintDebug( "  Item: %4i:  entity %5i (= %s), classname: %s.", i, g_strArStorage[i][entNumber], g_csItemPickName[ g_strArStorage[i][entPickedType] ], tmpStr );
    }
    
    PrintDebug("[rand] how many blindable stored: %4i", count);
    count = 0;
    
    PrintDebug("[rand] --------------- blinded entity list -----------------");
    
    new size = GetArraySize(g_hBlockedEntities);
    decl currentEnt[EntInfo];

    for (new i; i < size; i++)
    {
        GetArrayArray(g_hBlockedEntities, i, currentEnt[0]);
        
        if (currentEnt[hasBeenSeen]) { continue; }
        
        if (currentEnt[iEntity] != 0 && IsValidEntity(currentEnt[iEntity])) {
            GetEntityClassname( currentEnt[iEntity], tmpStr, sizeof(tmpStr) );
        } else {
            tmpStr = "";
        }
        
        count++;
        
        PrintDebug( "  BlindEnt: %4i:  entity %5i = classname: %s.", i, currentEnt[iEntity], tmpStr );
        
    }
    
    PrintDebug("[rand] how many blindable blinded: %4i", count);
}
*/

// for debugging item balance
DoItemsServerReport(full=false)
{
    PrintDebug("[rand] Randomized item table, for %i items:", g_iStoredEntities);
    
    new iGroupCount[INDEX_TOTAL];        // counts per index group
    new iItemCount[pickType];   // counts per item
    new iTotalRealItems = 0;    // how many non-no-item
    
    // weights
    new iWeight[INDEX_TOTAL];
    new iTotalWeight = 0;
    for (new i=INDEX_NOITEM; i < INDEX_TOTAL; i++)
    {
        iWeight[i] = GetConVarInt(g_hArCvarWeight[i]);
        iTotalWeight += iWeight[i];
    }
    
    new String: tmpStr[64];
    
    if (full) {
        PrintDebug("[rand] --------------- entity list -----------------");
    }
    
    g_iCountItemGnomes = 0;
    g_iCountItemCola = 0;
    g_iCountItemMedkits = 0;
    g_iCountItemDefibs = 0;
    
    for (new i=0; i < g_iStoredEntities; i++)
    {
        iItemCount[ g_strArStorage[i][entPickedType] ]++;
        
        // count towards group
        switch (_:g_strArStorage[i][entPickedType])
        {
            case PCK_NOITEM: { iGroupCount[INDEX_NOITEM]++; }
            case PCK_PISTOL: { iGroupCount[INDEX_PISTOL]++; } case PCK_PISTOL_MAGNUM: { iGroupCount[INDEX_PISTOL]++; }
            case PCK_SMG_MP5: { iGroupCount[INDEX_T1SMG]++; } case PCK_SMG: { iGroupCount[INDEX_T1SMG]++; } case PCK_SMG_SILENCED: { iGroupCount[INDEX_T1SMG]++; }
            case PCK_PUMPSHOTGUN: { iGroupCount[INDEX_T1SHOTGUN]++; } case PCK_SHOTGUN_CHROME: { iGroupCount[INDEX_T1SHOTGUN]++; }
            case PCK_RIFLE_SG552: { iGroupCount[INDEX_T2RIFLE]++; } case PCK_RIFLE: { iGroupCount[INDEX_T2RIFLE]++; } case PCK_RIFLE_AK47: { iGroupCount[INDEX_T2RIFLE]++; } case PCK_RIFLE_DESERT: { iGroupCount[INDEX_T2RIFLE]++; }
            case PCK_AUTOSHOTGUN: { iGroupCount[INDEX_T2SHOTGUN]++; } case PCK_SHOTGUN_SPAS: { iGroupCount[INDEX_T2SHOTGUN]++; }
            case PCK_HUNTING_RIFLE: { iGroupCount[INDEX_SNIPER]++; } case PCK_SNIPER_MILITARY: { iGroupCount[INDEX_SNIPER]++; } case PCK_SNIPER_SCOUT: { iGroupCount[INDEX_SNIPER]++; } case PCK_SNIPER_AWP: { iGroupCount[INDEX_SNIPER]++; }
            case PCK_MELEE: { iGroupCount[INDEX_MELEE]++; }
            case PCK_CHAINSAW: { iGroupCount[INDEX_T3]++; } case PCK_GRENADE_LAUNCHER: { iGroupCount[INDEX_T3]++; } case PCK_RIFLE_M60: { iGroupCount[INDEX_T3]++; }
            case PCK_EXPLOSIVE_BARREL: { iGroupCount[INDEX_CANISTER]++; } case PCK_GASCAN: { iGroupCount[INDEX_CANISTER]++; } case PCK_PROPANETANK: { iGroupCount[INDEX_CANISTER]++; } case PCK_OXYGENTANK: { iGroupCount[INDEX_CANISTER]++; } case PCK_FIREWORKCRATE: { iGroupCount[INDEX_CANISTER]++; }
            case PCK_AMMO: { iGroupCount[INDEX_AMMO]++; }
            case PCK_PAIN_PILLS: { iGroupCount[INDEX_PILL]++; } case PCK_ADRENALINE: { iGroupCount[INDEX_PILL]++; }
            case PCK_MOLOTOV: { iGroupCount[INDEX_THROWABLE]++; } case PCK_PIPEBOMB: { iGroupCount[INDEX_THROWABLE]++; } case PCK_VOMITJAR: { iGroupCount[INDEX_THROWABLE]++; }
            case PCK_FIRST_AID_KIT: { iGroupCount[INDEX_KIT]++; g_iCountItemMedkits++; } case PCK_DEFIBRILLATOR: { iGroupCount[INDEX_KIT]++; g_iCountItemDefibs++; }
            case PCK_UPG_LASER: { iGroupCount[INDEX_UPGRADE]++; } case PCK_UPG_EXPLOSIVE: { iGroupCount[INDEX_UPGRADE]++; } case PCK_UPG_INCENDIARY: { iGroupCount[INDEX_UPGRADE]++; }
            case PCK_JUNK: { iGroupCount[INDEX_JUNK]++; }
            case PCK_SILLY_GNOME: { iGroupCount[INDEX_SILLY]++; g_iCountItemGnomes++; } case PCK_SILLY_COLA: { iGroupCount[INDEX_SILLY]++; g_iCountItemCola++; }
            case PCK_SILLY_GIFT: { iGroupCount[INDEX_GIFT]++; }
        }
        
        if (g_strArStorage[i][entNumber] == 0) { continue; }
        
        if (IsValidEntity(g_strArStorage[i][entNumber])) {
            GetEntityClassname( g_strArStorage[i][entNumber], tmpStr, sizeof(tmpStr) );
        } else {
            tmpStr = "";
        }
        
        if (full) {
            PrintDebug( "  Item: %4i: entity %5i (= %s), classname: %s.", i, g_strArStorage[i][entNumber], g_csItemPickName[ g_strArStorage[i][entPickedType] ], tmpStr );
        }
    }
    
    if (full) { return; }
    
    iTotalRealItems = g_iStoredEntities - iItemCount[PCK_NOITEM];
    
    /*
    PrintDebug("[rand] --------------- item list -----------------");
    
    PrintDebug( "  %18s: %4i ( %5.1f%% /        ).", "no item", iItemCount[0], float(iItemCount[0]) / float(g_iStoredEntities) * 100.0 );
    PrintDebug( "  %18s: %4i ( %5.1f%% /        ).", g_csItemPickName[PCK_JUNK], iItemCount[PCK_JUNK], float(iItemCount[PCK_JUNK]) / float(g_iStoredEntities) * 100.0 );
    PrintDebug("");
    
    for (new i=PCK_PISTOL; i < _:PCK_DUALS; i++)
    {
        if (i == _:PCK_JUNK) { continue; }
        PrintDebug( "  %18s: %4i ( %5.1f%% / %5.1f%% ).", g_csItemPickName[i], iItemCount[i], float(iItemCount[i]) / float(g_iStoredEntities) * 100.0, float(iItemCount[i]) / float(iTotalRealItems) * 100.0 );
    }
    */
    PrintDebug("---------------------- type list --------------------------------------------------------- real items: %4i", iTotalRealItems);
    
    PrintDebug( "  %18s: %4i ( %5.1f%% /        ). Weighted at: %5.1f%%", "no item", iGroupCount[0], float(iGroupCount[0]) / float(g_iStoredEntities) * 100.0, float(iWeight[0]) / float(iTotalWeight) * 100.0 );
    PrintDebug( "  %18s: %4i ( %5.1f%% /        ). Weighted at: %5.1f%%", g_csItemTypeText[INDEX_JUNK], iGroupCount[INDEX_JUNK], float(iGroupCount[INDEX_JUNK]) / float(g_iStoredEntities) * 100.0, float(iWeight[INDEX_JUNK]) / float(iTotalWeight) * 100.0, float(iWeight[INDEX_JUNK]) / float(iTotalWeight) * 100.0  );
    PrintDebug("-----------------------------------------------------------------------------------------------------------");
    
    iTotalWeight = (iTotalWeight - iWeight[0]) - iWeight[INDEX_JUNK];
    
    for (new i=INDEX_PISTOL; i < _:INDEX_TOTAL; i++)
    {
        if (i == _:INDEX_JUNK) { continue; }
        PrintDebug( "  %18s: %4i ( %5.1f%% / %5.1f%% ). Weighted at: %5.1f%%, expected occurrence: %3i (diff.: %3i).",
                g_csItemTypeText[i], iGroupCount[i],
                float(iGroupCount[i]) / float(g_iStoredEntities) * 100.0, float(iGroupCount[i]) / float(iTotalRealItems) * 100.0,
                float(iWeight[i]) / float(iTotalWeight) * 100.0,
                RoundFloat( (float(iWeight[i]) / float(iTotalWeight)) * iTotalRealItems ),
                iGroupCount[i] - RoundFloat( (float(iWeight[i]) / float(iTotalWeight)) * iTotalRealItems )
            );
    }
    
    PrintDebug("-----------------------------------------------------------------------------------------------------------");
    
}