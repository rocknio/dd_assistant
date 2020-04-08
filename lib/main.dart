import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';
import 'package:ddassistant/dingding_info.dart';
import 'package:datetime_picker_formfield/datetime_picker_formfield.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:bot_toast/bot_toast.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:analog_clock/analog_clock.dart';
import 'package:dio/dio.dart';
import 'package:wakelock/wakelock.dart';

enum workType {work, rest}
enum dayType {work, rest, holiday, unknown}
enum workingStatus {idle, waitForLaunch, processing}

void main() {
	WidgetsFlutterBinding.ensureInitialized();

	// 强制竖屏
	SystemChrome.setPreferredOrientations([
		DeviceOrientation.portraitUp,
		DeviceOrientation.portraitDown
	]);

	runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BotToastInit(
      child: MaterialApp(
        title: '钉钉辅助',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        navigatorObservers: [BotToastNavigatorObserver()],
        home: MyHomePage(title: '钉钉辅助'),
      ),
    );
  }
}

class TodayType {
	String day;
	dayType type;

	TodayType({this.day, this.type});
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
	Application dingdingApp;
	MemoryImage dingdingIcon;
	bool editAble = true;
	DateTime workTime, restTime;
	Timer _loopTimer;
	final String dingdingPackageName = "com.alibaba.android.rimet";
	final String selfPackageName = "com.example.ddassistant";
	SharedPreferences prefs;
	Application selfApp;
	TodayType todayType;
	workingStatus status = workingStatus.idle;

	void _getSelfApp() async {
		if (selfApp == null) {
			selfApp = await DeviceApps.getApp(selfPackageName);
		}
	}

  void _getDingdingApp() async {
		if (dingdingApp == null) {
			Application _app = await DeviceApps.getApp(dingdingPackageName, true);
			setState(() {
				dingdingApp = _app;
				dingdingIcon = _app is ApplicationWithIcon ? MemoryImage(_app.icon) : null;
			});
		}
  }

  Future<void> initSharedPreferences() async {
  	prefs = await SharedPreferences.getInstance();

	  if (prefs.getInt("workTimeHour") != null && prefs.getInt("workTimeMinute") != null) {
	  	setState(() {
			  workTime = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, prefs.getInt("workTimeHour"), prefs.getInt("workTimeMinute"));
	  	});
	  }

	  if (prefs.getInt("workTimeHour") != null && prefs.getInt("restTimeMinute")!= null) {
	  	setState(() {
			  restTime = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, prefs.getInt("restTimeHour"), prefs.getInt("restTimeMinute"));
	  	});
	  }
  }

  void _setKeepScreenOn() async {
		bool isEnable = await Wakelock.isEnabled;
		if (!isEnable) {
			Wakelock.enable();
		}
  }

  @override
  void initState() {
	  _getDingdingApp();
	  _getSelfApp();
	  _setKeepScreenOn();

	  initSharedPreferences();

	  WidgetsBinding.instance.addObserver(this);

    super.initState();
  }

  @override
  void dispose() {
	  cancelLoopTimer();

	  WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("didChangeAppLifecycleState = $state");

    switch (state) {
	    case AppLifecycleState.inactive:
	    	cancelLoopTimer();
	    	break;
      case AppLifecycleState.resumed:
      	cancelLoopTimer();
      	startAssistantLoop();
        break;
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        break;
    }

    super.didChangeAppLifecycleState(state);
  }

	void cancelLoopTimer() {
		if (_loopTimer != null && _loopTimer.isActive) {
			_loopTimer.cancel();
			_loopTimer = null;
			setState(() {
				status = workingStatus.idle;
			});
		}
	}

	void startAssistantLoop() {
  	if (prefs == null) {
  		BotToast.showSimpleNotification(
				title: "初始化未完成！",
			  duration: Duration(seconds: 3),
		  );

		  return;
	  }

  	if (dingdingApp == null) {
		  BotToast.showSimpleNotification(
			  title: "安装钉钉了么？",
			  duration: Duration(seconds: 3),
		  );

  		return;
	  }

  	setState(() {
  	  status = workingStatus.processing;
  	});

		_loopTimer = Timer.periodic(Duration(seconds: 30), (_) {
			_launchDingding();
		});
	}

	void openSelf() {

	}

	Future<bool> openDingding() async {
		bool _isLaunched = false;
		String currentTime;

		currentTime = DateTime.now().toString();
		_isLaunched = await DeviceApps.openApp(dingdingPackageName);
		print("Open Dingding at: $currentTime, result = $_isLaunched");

		if (_isLaunched) {
			// 等待30秒，待钉钉启动后，重新启动自己
			Timer(Duration(seconds: 30), () async {
				openSelf();
				Timer(Duration(minutes: 1), () {
					startAssistantLoop();
				});
			});
		} else {
			BotToast.showSimpleNotification(
				title: "钉钉启动失败",
				duration: Duration(seconds: 3),
			);
		}

		Timer(Duration(minutes: 1), () {
			startAssistantLoop();
		});

		return _isLaunched;
	}

	void calcDelay() {
		var rng = Random();
		int delta = rng.nextInt(15);
		String tmp = DateTime.now().add(Duration(minutes: delta)).toString();
		print("打开钉钉时间：$tmp");
		BotToast.showSimpleNotification(
			title: "打开钉钉时间",
			subTitle: "$tmp",
			duration: Duration(seconds: 3),
			align: Alignment.bottomCenter
		);

		status = workingStatus.waitForLaunch;
		Timer(Duration(minutes: delta), () {
			openDingding();
		});
	}

	/*
	API地址:http://tool.bitefu.net/jiari/
	新增VIP通道功能更全:http://tool.bitefu.net/jiari/vip.php
	功能特点
	检查具体日期是否为节假日，工作日对应结果为 0, 休息日对应结果为 1, 节假日对应的结果为 2；
	* */
	Future<dayType> checkHoliday() async {
		var currentDay = DateFormat("yyyyMMdd").format(DateTime.now());
		String url = "http://tool.bitefu.net/jiari/?d=" + currentDay;
		dayType ret = dayType.unknown;

		final resp = await Dio().get(url);

		switch (resp.data) {
			case 0:
				ret = dayType.work;
				break;
			case 1:
				ret = dayType.rest;
				break;
			case 2:
				ret = dayType.holiday;
				break;
		}

		return ret;
	}

	void _launchDingding() async {
		if (workTime == null || restTime == null) {
			return;
		}

		String tmp = DateTime.now().day.toString().padLeft(2, '0');
		if (todayType == null || tmp != todayType.day) {
			dayType tmp = await checkHoliday();
			todayType = TodayType()
				..day = DateTime.now().day.toString().padLeft(2, '0')
				..type = tmp;
		}

		if (todayType.type != dayType.work) {
			return;
		}

		cancelLoopTimer();

		int currentHour, currentMinute;
		currentHour = DateTime.now().hour;
		currentMinute = DateTime.now().minute;

		if (currentHour == workTime.hour && currentMinute == workTime.minute) {
			// 上班
			calcDelay();
		} else if (currentHour == restTime.hour && currentMinute == restTime.minute) {
			// 下班
			calcDelay();
		} else {
			startAssistantLoop();
		}
	}

	void setTime(workType type, DateTime time) async {
  	if (type == workType.work) {
  		workTime = time;
		  await prefs.setInt("workTimeHour", workTime.hour);
		  await prefs.setInt("workTimeMinute", workTime.minute);
	  } else if (type == workType.rest) {
  		restTime = time;
		  await prefs.setInt("restTimeHour", restTime.hour);
		  await prefs.setInt("restTimeMinute", restTime.minute);
	  }
	}

  @override
  Widget build(BuildContext context) {
  	var card = SizedBox(
		  height: 210.0,
		  child: Card(
			  elevation: 15.0,
			  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14.0))),
			  child: Column(
				  children: <Widget>[
				  	ListTile(
						  title: Text("时间设置", style: TextStyle(fontWeight: FontWeight.w500),),
						  leading: Icon(Icons.settings_applications, color: Colors.blue,),
					  ),
					  Divider(),
					  Padding(
					    padding: const EdgeInsets.symmetric(horizontal: 20.0),
					    child: DateTimeField(
							  format: DateFormat("HH:mm"),
							  readOnly: editAble,
							  decoration: InputDecoration(
									labelText: workTime != null ? workTime.hour.toString().padLeft(2, '0') + ":" + workTime.minute.toString().padLeft(2, '0') : '上班时间：',
									hasFloatingPlaceholder: false,
								  suffixIcon: Icon(Icons.work),
							  ),
							  onShowPicker: (context, currentValue) async {
							    final time = await showTimePicker(
										  context: context,
										  initialTime: workTime != null ? TimeOfDay(hour: workTime.hour, minute: workTime.minute) : TimeOfDay(hour: 8, minute: 40),
								  );

							    return DateTimeField.convert(time);
							  },
							  onChanged: (dt) {
								  setTime(workType.work, dt);
							  },
					    ),
					  ),
					  Padding(
					    padding: const EdgeInsets.symmetric(horizontal: 20.0),
					    child: DateTimeField(
						  format: DateFormat("HH:mm"),
						  readOnly: editAble,
						  decoration: InputDecoration(
								  labelText: restTime != null ? restTime.hour.toString().padLeft(2, '0') + ":" + restTime.minute.toString().padLeft(2, '0') : '下班时间：',
								  hasFloatingPlaceholder: false
						  ),
						  onShowPicker: (context, currentValue) async {
							  final time = await showTimePicker(
							   context: context,
							   initialTime: restTime != null ? TimeOfDay(hour: restTime.hour, minute: restTime.minute) : TimeOfDay(hour: 18, minute: 00),
							  );

							  return DateTimeField.convert(time);
						  },
						  onChanged: (dt) {
							  setTime(workType.rest, dt);
						  },
					    ),
					  ),
				  ],
			  ),
		  ),
	  );

  	Widget getFloatingButtonWidget() {
  		switch (status) {
			  case workingStatus.idle:
			  	return Icon(Icons.send, color: Colors.white,);
			  case workingStatus.waitForLaunch:
				  return ClipOval(
						  child: Image.asset("assets/images/loading.gif",fit: BoxFit.cover,width: 240,height: 240,)
				  );
			  case workingStatus.processing:
			  default:
			    return Icon(Icons.stop, color: Colors.white,);
		  }
	  }

	  Color getFloatingButtonBackgroundColor() {
  		switch (status) {
			  case workingStatus.processing:
			  	return Colors.red;
		    case workingStatus.idle:
			  default:
		      return Colors.green;
		  }
	  }

  	return Scaffold(
		  appBar: AppBar(
			  title: Text(widget.title),
			  elevation: 5.0,
		  ),
		  body: Column(
			  children: <Widget>[
			  	Expanded(
					  child: Container(
				      decoration: BoxDecoration(color: Colors.blue),
							child: DingdingInfo(dingdingApp: dingdingApp, dingdingIcon: dingdingIcon,)
					  ),
					  flex: 1,
				  ),
				  Expanded(
					  child: card,
					  flex: 3,
				  ),
				  Expanded(
					  child: AnalogClock(
//						  decoration: BoxDecoration(
//							  border: Border.all(width: 2.0, color: Colors.black),
//							  color: Colors.transparent,
//							  shape: BoxShape.circle
//						  ),
						  width: 180.0,
						  isLive: true,
						  hourHandColor: Colors.black,
						  minuteHandColor: Colors.black,
						  showSecondHand: true,
						  secondHandColor: Colors.redAccent,
						  numberColor: Colors.black87,
						  showNumbers: true,
						  textScaleFactor: 1.4,
						  showTicks: true,
						  showDigitalClock: true,
					  ),
					  flex: 3,
				  )
			  ],
		  ),
		  floatingActionButton: FloatingActionButton(
				backgroundColor: getFloatingButtonBackgroundColor(),
			  onPressed: () async {
			  	if (status == workingStatus.idle) {
					  startAssistantLoop();
				  } else {
			  		cancelLoopTimer();
				  }
			  },
//			  child: Icon(Icons.send, color: Colors.white,),
		    child: getFloatingButtonWidget()
		  ),
	  );
  }
}
