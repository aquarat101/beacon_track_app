# Keep all classes in linesdk package
-keep class com.linecorp.linesdk.** { *; }

# Keep BR class ที่ R8 บอกหาย
-keep class com.linecorp.linesdk.BR { *; }

# ไม่ต้องแสดง warning ของ BR
-dontwarn com.linecorp.linesdk.BR

# Keep data binding adapters
-keepclassmembers class * {
    @androidx.databinding.BindingAdapter *;
}

# Keep ViewDataBinding fields
-keepclassmembers class * extends androidx.databinding.ViewDataBinding {
    public static final int _all;
}

# Keep LiveData classes (ช่วยลดปัญหาเกี่ยวกับ LiveData)
-keep class androidx.lifecycle.MutableLiveData { *; }
-keep class androidx.lifecycle.LiveData { *; }
