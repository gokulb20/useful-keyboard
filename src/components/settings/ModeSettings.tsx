import React, { useState, useEffect, useCallback } from "react";
import { useTranslation } from "react-i18next";
import { Plus, Pencil, Trash2, Check } from "lucide-react";
import type { ProcessingMode } from "@/bindings";
import { commands } from "@/bindings";
import { SettingsGroup } from "../ui/SettingsGroup";
import { Button } from "../ui/Button";
import { ModeEditor } from "./ModeEditor";

export const ModeSettings: React.FC = () => {
  const { t } = useTranslation();
  const [modes, setModes] = useState<ProcessingMode[]>([]);
  const [activeModeId, setActiveModeId] = useState<string>("clean");
  const [editingMode, setEditingMode] = useState<ProcessingMode | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  const loadModes = useCallback(async () => {
    const modesResult = await commands.getProcessingModes();
    if (modesResult.status === "ok") {
      setModes(modesResult.data);
    }
    const activeResult = await commands.getActiveModeId();
    if (activeResult.status === "ok") {
      setActiveModeId(activeResult.data);
    }
  }, []);

  useEffect(() => {
    loadModes();
  }, [loadModes]);

  const handleSetActive = async (modeId: string) => {
    const result = await commands.setActiveMode(modeId);
    if (result.status === "ok") {
      setActiveModeId(modeId);
    }
  };

  const handleCreate = async (
    name: string,
    description: string,
    prompt: string,
  ) => {
    const result = await commands.createProcessingMode(
      name,
      description,
      prompt,
    );
    if (result.status === "ok") {
      setIsCreating(false);
      await loadModes();
    }
  };

  const handleUpdate = async (
    name: string,
    description: string,
    prompt: string,
  ) => {
    if (!editingMode) return;
    const result = await commands.updateProcessingMode(
      editingMode.id,
      name,
      description,
      prompt,
    );
    if (result.status === "ok") {
      setEditingMode(null);
      await loadModes();
    }
  };

  const handleDelete = async (id: string) => {
    const result = await commands.deleteProcessingMode(id);
    if (result.status === "ok") {
      if (editingMode?.id === id) {
        setEditingMode(null);
      }
      await loadModes();
    }
  };

  const builtinModes = modes.filter((m) => m.is_builtin);
  const customModes = modes.filter((m) => !m.is_builtin);

  return (
    <div className="max-w-3xl w-full mx-auto space-y-6">
      <SettingsGroup
        title={t("settings.modes.title")}
        description={t("settings.modes.description")}
      >
        {builtinModes.map((mode) => (
          <ModeRow
            key={mode.id}
            mode={mode}
            isActive={mode.id === activeModeId}
            onSetActive={() => handleSetActive(mode.id)}
          />
        ))}
      </SettingsGroup>

      {customModes.length > 0 && (
        <SettingsGroup title={t("settings.modes.custom")}>
          {customModes.map((mode) => (
            <ModeRow
              key={mode.id}
              mode={mode}
              isActive={mode.id === activeModeId}
              onSetActive={() => handleSetActive(mode.id)}
              onEdit={() => {
                setIsCreating(false);
                setEditingMode(mode);
              }}
              onDelete={() => handleDelete(mode.id)}
            />
          ))}
        </SettingsGroup>
      )}

      {(isCreating || editingMode) && (
        <ModeEditor
          mode={editingMode}
          isCreating={isCreating}
          onSave={isCreating ? handleCreate : handleUpdate}
          onCancel={() => {
            setIsCreating(false);
            setEditingMode(null);
          }}
        />
      )}

      {!isCreating && !editingMode && (
        <div className="px-4">
          <Button
            variant="secondary"
            size="sm"
            onClick={() => {
              setEditingMode(null);
              setIsCreating(true);
            }}
          >
            <span className="flex items-center gap-1.5">
              <Plus size={14} />
              {t("settings.modes.addMode")}
            </span>
          </Button>
        </div>
      )}
    </div>
  );
};

interface ModeRowProps {
  mode: ProcessingMode;
  isActive: boolean;
  onSetActive: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
}

const ModeRow: React.FC<ModeRowProps> = ({
  mode,
  isActive,
  onSetActive,
  onEdit,
  onDelete,
}) => {
  return (
    <div className="flex items-center justify-between px-4 py-3">
      <div
        className="flex items-center gap-3 flex-1 cursor-pointer min-w-0"
        onClick={onSetActive}
      >
        <div
          className={`w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors ${
            isActive
              ? "border-background-ui bg-background-ui"
              : "border-mid-gray/40"
          }`}
        >
          {isActive && <Check size={12} className="text-white" />}
        </div>
        <div className="min-w-0">
          <p className="text-sm font-medium truncate">{mode.name}</p>
          <p className="text-xs text-mid-gray truncate">{mode.description}</p>
        </div>
      </div>
      <div className="flex items-center gap-1 shrink-0">
        {onEdit && (
          <button
            onClick={onEdit}
            className="p-1.5 rounded hover:bg-mid-gray/10 text-mid-gray hover:text-text transition-colors"
          >
            <Pencil size={14} />
          </button>
        )}
        {onDelete && (
          <button
            onClick={onDelete}
            className="p-1.5 rounded hover:bg-red-500/10 text-mid-gray hover:text-red-400 transition-colors"
          >
            <Trash2 size={14} />
          </button>
        )}
      </div>
    </div>
  );
};
