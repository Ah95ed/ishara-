package com.Ishara.iq.ishara.model

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * محمل ومطابق قاموس المفردات (VocabularyLoader)
 * يقرأ قاموس الكلمات (ishara_vocab.json) من مجلد الأصول ويحول معرّفات CTC إلى كلمات عربية.
 */
class VocabularyLoader(private val context: Context) {

    companion object {
        private const val TAG = "VocabularyLoader"
        private const val ASSET_PATH = "assets/models/ishara_vocab.json"
    }

    private val vocabMap = mutableMapOf<Int, String>()
    var isLoaded: Boolean = false
        private set

    /**
     * تحميل القاموس
     */
    fun loadVocabulary(): Boolean {
        try {
            val assetManager = context.assets
            // محاولة الحصول على المسار المترجم من Flutter Loader
            val lookupKey = try {
                FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(ASSET_PATH)
            } catch (e: Exception) {
                "flutter_assets/$ASSET_PATH"
            }

            val inputStream = try {
                assetManager.open(lookupKey)
            } catch (e: Exception) {
                try {
                    assetManager.open("flutter_assets/$ASSET_PATH")
                } catch (e2: Exception) {
                    assetManager.open(ASSET_PATH)
                }
            }

            val reader = BufferedReader(InputStreamReader(inputStream, Charsets.UTF_8))
            val jsonString = reader.use { it.readText() }
            val json = JSONObject(jsonString)

            vocabMap.clear()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val id = key.toIntOrNull()
                if (id != null) {
                    vocabMap[id] = json.getString(key)
                }
            }

            isLoaded = true
            Log.i(TAG, "Vocabulary loaded successfully: ${vocabMap.size} classes.")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error loading vocabulary: ${e.message}", e)
            isLoaded = false
            return false
        }
    }

    /**
     * تحويل معرّف CTC إلى كلمة عربية
     */
    fun mapIdToGloss(id: Int): String {
        return vocabMap[id] ?: "UNKNOWN_$id"
    }

    /**
     * تحويل قائمة معرّفات CTC إلى قائمة كلمات عربية
     */
    fun mapIdsToGlosses(ids: IntArray): List<String> {
        return ids.map { mapIdToGloss(it) }
    }

    val totalClasses: Int get() = vocabMap.size
}
