use crate::settings::{get_settings, write_settings, ProcessingMode};
use crate::tray;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::AppHandle;

#[tauri::command]
#[specta::specta]
pub fn get_processing_modes(app: AppHandle) -> Result<Vec<ProcessingMode>, String> {
    let settings = get_settings(&app);
    Ok(settings.processing_modes)
}

#[tauri::command]
#[specta::specta]
pub fn get_active_mode_id(app: AppHandle) -> Result<String, String> {
    let settings = get_settings(&app);
    Ok(settings.active_mode_id)
}

#[tauri::command]
#[specta::specta]
pub fn set_active_mode(app: AppHandle, mode_id: String) -> Result<(), String> {
    let mut settings = get_settings(&app);

    // Verify the mode exists
    if !settings.processing_modes.iter().any(|m| m.id == mode_id) {
        return Err(format!("Mode '{}' not found", mode_id));
    }

    settings.active_mode_id = mode_id;
    write_settings(&app, settings);

    // Rebuild tray menu to update the checkmark
    tray::update_tray_menu(&app, &tray::TrayIconState::Idle, None);

    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn create_processing_mode(
    app: AppHandle,
    name: String,
    description: String,
    prompt: String,
) -> Result<ProcessingMode, String> {
    let mut settings = get_settings(&app);

    let id = format!(
        "custom_{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
    );
    let mode = ProcessingMode {
        id: id.clone(),
        name,
        description,
        prompt,
        is_builtin: false,
    };

    settings.processing_modes.push(mode.clone());
    write_settings(&app, settings);

    // Rebuild tray menu to show the new mode
    tray::update_tray_menu(&app, &tray::TrayIconState::Idle, None);

    Ok(mode)
}

#[tauri::command]
#[specta::specta]
pub fn update_processing_mode(
    app: AppHandle,
    id: String,
    name: String,
    description: String,
    prompt: String,
) -> Result<(), String> {
    let mut settings = get_settings(&app);

    let mode = settings
        .processing_modes
        .iter_mut()
        .find(|m| m.id == id)
        .ok_or_else(|| format!("Mode '{}' not found", id))?;

    if mode.is_builtin {
        return Err("Cannot modify built-in modes".to_string());
    }

    mode.name = name;
    mode.description = description;
    mode.prompt = prompt;

    write_settings(&app, settings);

    // Rebuild tray menu in case name changed
    tray::update_tray_menu(&app, &tray::TrayIconState::Idle, None);

    Ok(())
}

#[tauri::command]
#[specta::specta]
pub fn delete_processing_mode(app: AppHandle, id: String) -> Result<(), String> {
    let mut settings = get_settings(&app);

    let mode = settings
        .processing_modes
        .iter()
        .find(|m| m.id == id)
        .ok_or_else(|| format!("Mode '{}' not found", id))?;

    if mode.is_builtin {
        return Err("Cannot delete built-in modes".to_string());
    }

    settings.processing_modes.retain(|m| m.id != id);

    // If the deleted mode was active, fall back to "clean"
    if settings.active_mode_id == id {
        settings.active_mode_id = "clean".to_string();
    }

    write_settings(&app, settings);

    // Rebuild tray menu
    tray::update_tray_menu(&app, &tray::TrayIconState::Idle, None);

    Ok(())
}
